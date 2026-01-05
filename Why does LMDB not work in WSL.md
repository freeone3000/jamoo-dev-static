---
share: true
title: "Why does LMDB not work in WSL?"
date: 2024-10-31
---
# Why does LMDB not work in WSL?

Finishing off spooky season with a *👻spooky explainer👻*

Short answer is: It does, except on your NTFS drives; the NTFS-for-WSL driver does not properly determine the size of sparse files.

Longer answer follows:

## Notation
The following uses linux man page notation: `command(1)` is a userland command, `function(3)` is a C library function, and `syscall(2)` is a syscall.
It is assumed your program is written in C, and is running on x86 linux. Other architectures and OSes have similar concepts, but the details differ.

## How Computer Memory is Allocated (in Linux)
x86 offers two different ways of accessing memory: real mode, where the addresses you ask for in memory are the actual physical addresses on the RAM chips,
and protected mode, where the addresses you ask for are virtual addresses mapped to physical addresses via LUT. Since on x86 protected mode is required for *32-bit*,
much less 64-bit, operation, just assume all x86 computer systems boot directly into protected mode.

Memory paging is an OS feature of protected mode (versus real mode). Instead of one contiguous chunk, you are given memory pages, which may or may not be contiguous, to hold your data. Pages are all the same size.
Each page is owned by one process (mostly, we’re actually going there). This counters memory fragmentation, by giving out larger "blocks" to individual programs we can limit the number of "unusable" space due to fragmentation - every allocation is
either a page or less than a page, so an allocator is able to distribute entire pages. This allows for intra-page lookups to be continuous and cachable, which is important to keep arrays fast.
A second feature, virtual memory, allows us to lie about where memory is located. This means that discontinuous pages in physical RAM can be presented as continuous pages to a program, allowing an array to occupy multiple "continuous" pages that are not,
in fact, continuous in physical RAM. This is a legacy of C code, which operates *as if* it was in real mode, even when it's not.

Why do we take such pains to counter memory fragmentation? I present the following scenario:
Think about having 5 pages and a linear (ie, bad) allocator. If a 2-page program starts, then a 1-page, the first 3 pages are taken. The 2-page program exits, then a 4-page program starts.
Without virtual memory addresses, 4 pages of continuous memory are unavailable. With virtual memory, the program can get pages 1,2,4,5 no problem.
OR the OS can actually move the 1-page program! Or do both! It lies about the addresses so that the process’s view of memory can remain consistent with whatever a PDP-11 did, so that C programs are happy.

The addresses are lies, but you still need a way to ask for this lie. There is only one system call currently used for memory allocation in Linux: `mmap(2)`. Various C functions, including
`malloc(3)`, `calloc(3)`, and notably `mmap(3)` map to `mmap(2)` (as well as some interesting cases like `fread(3)`, which we'll get to!). `mmap(2)` allows a process to ask for one or more pages, optionally backed by a file, into its process space.
It can even ask what the returned pointer should be! It’s a lie anyway, so why not ask for the lie you want? And since it’s a lie… the pages don’t actually have to be mapped yet.

You can request the memory be zero-filled. Which ACTUALLY means the pages without another mapping are mapped to the zero page, which is a special memory page that is always all zero (“Without another mapping” because if you request file backing… we’ll get to that).
When you write to a page aliased to the zero-page, that is when a new page is mapped in, and your write goes to that page. This is completely transparent to the process, which just sees a memory write take slightly longer than usual.
When you asked for `fread(3)`, this maps to `mmap(2)` on modern systems (visible via `strace(1)`): the file gets opened, and then the file contents are mapped to pages in memory as anything else. This happens transparently, and introduces an interesting
duality in this interface: Files and memory *are the same* from a program's standpoint. And `mmap(2)` isn’t just usable through `malloc(3)`! You can also just call `mmap(2)` (or `mmap(3)`) directly. If you wanna play with the magic, it’s there.

Which leads us to the synthesis: **file-backed memory**. Let's call `mmap(3)` and request a 1TiB page backed by a specific file. When we write to this memory region, the writes go to the file with the same byte offset as the memory write.
This write also happens to memory - you're writing to a memory page, but also to the disk, transparently. If you were to write structs or any other complex data to this region, it would be persisted as bytes to disk.
Portability would require some additional steps, like enforcing endianness, but you could stop here. You essentially get free persistence, and it also means loading is fast because you don’t have to parse it. 

But what if you need to resize the file? If you remap a mmaped file, you are not guaranteed the same pointer, despite any request - and if this pointer changes, all your references to the old pointer are invalid. You must remap all references,
since the old pointer was sent elsewhere by the OS. This is a bit of a pain, so we decided to not do it.

All major OSes also support something called sparse files. Sparse files are files where regions of zeroes are not actually stored on disk, but are instead represented as metadata in the filesystem.
When you read from a sparse region, the filesystem returns zeroes. When you write to a sparse region, the filesystem allocates space on disk for that region and writes your data. This is *very close* to virtual memory
and zero-page mapping, which is how it's implemented in practice when `mmap(3)`ing the file. The file is returned with proper memory size, but the pages are zero-mapped, so actual RAM isn't used.

This is what LMDB uses - a sparse file, mmap'd into memory, to back its database, at the maximum possible size. File sparsity prevents it from using too much disk, mmap's behaviour with sparse files prevents it from using too much RAM.
it's clear, efficient, modern, and takes advantage of documented behaviours of other layers of the stack. What could possibly go wrong?

## The Windows Subsystem for Linux version 2

A bit about the Windows Subsystem for Linux version 2.

The Windows Subsystem for Linux version 1 was an API translation layer, bringing the linux userland and executable format to natively parse on windows. A true subsystem! This is a good and honest endeavor! Reverse-WINE in all of its glory!

It didn’t work. It potentially *couldn’t* work. All major operating systems share a common ancestor, SYSV UNIX, except windows, who is derived from VMS.

*👽 It’s an alien 🛸*

Fundamental differences in the execution, implementation, and concept of syscalls (notably, `mmap(2)`) caused Microsoft to scrap WSL1 in favor of WSL2. **WSL2 is Linux in a VM.**

It’s a very good VM! It automatically does things like inherit runtime permissions, use Windows drivers for things like CUDA and sound, can open a display on the host, many many good things.
It can also natively access host-partition files through the wsl-ntfs driver, which is... not great. 

Many problems are related to performance, but I just ran into one related to sparse files. They always report as their extents rather than their mapped regions, even for sparse files.
This means, to this driver and only this driver, our 1TB files were actually 1TB. Even when mmap'd as sparse. And **that's why you get a NoSpaceLeftOnDevice error trying to run LMDB with a large region size on WSL on NTFS.**