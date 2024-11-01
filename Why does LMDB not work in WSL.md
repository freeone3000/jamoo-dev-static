---
share: true
title: "Why does LMDB not work in WSL?"
date: 2024-10-31
---
# Why does LMDB not work in WSL?

Finishing off spooky season with a *👻spooky explainer👻*

Short answer is: It does, except on your NTFS drives; the NTFS-for-WSL driver does not properly determine the size of sparse files.

Longer answer follows:

*This was written as a series of discord messages to my girlfriend, so it's not fully edited. Accuracy is functionally correct, but may not be totally accurate. Email me your corrections and I'll footnote them with credit!*

## How Computer Memory is Allocated (in Linux)
Usually computer memory is allocated with malloc but malloc is secretly two system calls in a trenchcoat, mmap and sbrk.
sbrk sets the “break” between your process’s memory max extent and the next one, the name is a bit historical since we use virtual memory now.

Virtual memory is a feature of protected mode (versus real mode). Instead of one contiguous chunk, you are given memory pages, which may or may not be contiguous, to hold your data. Pages are all the same size, and your pointers essentially point to page_start+offset_into_page
Each page is owned by one process (mostly, we’re actually going there). This counters memory fragmentation, because the addresses you get back are not real addresses! They’re mapped!

Think about having 5 pages and a linear (ie, bad) allocator. If a 2-page program starts, then a 1-page, the first 3 pages are taken. The 2-page program exists, then a 4-page program starts.
With virtual memory, the program can get pages 1,2,4,5 no problem.
OR the OS can actually move the 1-page program! Or do both! It lies about the addresses so that the process’s view of memory can remain consistent with whatever a PDP-11 did, so that C programs are happy.

So that’s sbrk + vmem. Let’s get into the other call, mmap.
The addresses are lies, but you still need a way to ask for a page. mmap allows a process to ask for one or more pages, optionally backed by a file, into its process space. It can even ask what the returned pointer should be!
It’s a lie anyway, so why not ask for the lie you want? And since it’s a lie… the pages don’t actually have to be mapped yet.

You can request the memory be zero-filled. Which ACTUALLY means the pages without another mapping are mapped to the zero page, which is a special memory page that is always all zero (“Without another mapping” bc if you request file backing… we’ll get to that).
When you write to a page aliased to the zero-page, that is when a new page is mapped in, and your write goes to that page, but to the process, it can’t tell, it looks the same.
But mmap isn’t just usable through malloc. You can also just call mmap directly. If you wanna play with the magic, it’s there.

So we call mmap and request a 1TB page backed by a specific file. When we write to this memory region, the writes go to the file with the same byte offset as the memory write. They're also in memory since it's the same page.
You essentially get free persistence, and it also means loading is fast because you don’t have to parse it. (There’s some stuff for portability here, like enforcing endianness and so on, but it mostly just does work this way.)

If you remap a mmaped file, though, you are not guaranteed the same pointer. Because you may also be using it elsewhere, and in order to keep consistency, the OS has to keep its lies straight. Which means if we remap and get back a different address, we have to invalidate all of our extant handles… except we might not know how many there are… unless we make our own garbage collector…
So we decided to Just Don't for this project. We allocate one 1TiB, it’s all empty anyway, Bob’s your uncle. But we backed it with a file, so, does that mean we have a 1TiB file? Not quite.

All major OSes also support “sparse files”, or, files with extants larger than… it’s mmap in reverse, it’s that, I explained virtual memory, it’s that as a file. If you map out a 1TiB sparse file, the actual usage is 4KiB or whatever the minimum file size for your FS is. There's some overhead for the mapping table but actually very little, and in general you can have very large files sparsely populated for free. They look a bit weird in `ls` since the default is the `st_size`, but "apparent size" and `du` give accurate figures.
You can create these with `truncate` and `fallocate -s`. But also, mmap has a flag to use these! and it works great! even on Windows! what could go wrong?

## The goddamn windows subsystem for linux version 2

So the goddamn Windows Subsystem for Linux Version 2.

WSL1 was an API translation layer, bringing the linux userland and executable format to natively parse on windows. A true subsystem! This is a good and honest endeavor!

It didn’t work and potentially couldn’t work. All major operating systems share a common ancestor, SYSV UNIX, except fucking windows, who is derived from VMS.

*👽 It’s an alien 🛸*

Fundamental differences in the execution, implementation, and concept of syscalls brought us to MSFT scrapping WSL1 in favor of WSL2, which is Linux in a VM. 
It’s a very good VM! It automatically does things like inherit runtime permissions, use windows drivers for things like CUDA and sound, can open a display on the host, many many good things
It can also natively access host-partition files through the wsl-ntfs driver, which is not great. 

Many problems are related to performance, but I just ran into one related to sparse files. They always report as their extants rather than their mapped regions
which means, to this driver and only this driver, our 1TB files were actually 1TB. and **that's why you get a NoSpaceLeftOnDevice error trying to run LMDB with a large region size on WSL on NTFS.**