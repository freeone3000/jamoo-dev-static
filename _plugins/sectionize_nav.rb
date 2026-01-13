# ruby
require 'nokogiri'

def sectionize_node(node, cur_heading_level)
  # Store original children before we modify the node
  original_children = node.children.to_a

  # Clear the node's children so we can rebuild with sections
  node.children.remove

  cur_section = Nokogiri::XML::Node.new('section', node.document)
  node.add_child(cur_section)

  original_children.each do |child|
    if child.element? && child.name.match?(/^h([1-6])$/)
      heading_level = child.name[1].to_i
      # if we're the top-level, set our current heading level to the first encountered heading
      if cur_heading_level == nil
        cur_heading_level = heading_level
      end
      if heading_level <= cur_heading_level # finish off the current section and start a new one
        # find the correct parent
        tgt_section = cur_section
        section_heading_level = cur_heading_level
        while tgt_section.parent && tgt_section.parent.name == 'section' && section_heading_level >= heading_level
          tgt_section = tgt_section.parent
          section_heading_level = tgt_section.first_element_child.name[1..].to_i
        end
        cur_section = Nokogiri::XML::Node.new('section', node.document)
        cur_section.add_child(child)
        tgt_section.add_child(cur_section)
      else
        # heading is a sub-heading; make a new subsection
        section = Nokogiri::XML::Node.new('section', node.document)
        section.add_child(child)
        cur_section.add_child(section)
        cur_section = section
      end
    else
      # Regular content, just add it to the current section
      cur_section.add_child(child)
    end
  end

  # Add all sections back to the parent node
  node.add_child(cur_section)
end

Jekyll::Hooks.register [:pages, :documents], :post_render do |page|
  next unless ['.html', '.htm'].include?(page.output_ext) && page.output

  Jekyll.logger.debug "sectionize: processing #{page.url} (ext=#{page.output_ext})"

  doc = Nokogiri::HTML(page.output)

  parent = doc.css('nav')

  parent.each do |nav|
    sectionize_node nav, nil
  end

  page.output = doc.to_html
end
