# UmmMultiSelect is used for multi-select field

# :nodoc:
class UmmMultiSelect < UmmSelect
  def default_value
    ['']
  end

  def ui_options
    options_for_select(schema_fragment.fetch('items', {}).fetch('enum', []).sort, element_value)
  end

  def title
    schema.fetch_key_leaf(form_fragment['key']).titleize
  end

  def element_properties(element)
    super(element).merge(multiple: true)
  end

  def render_preview
    content_tag(:ul) do
      element_value.each do |value|
        concat content_tag(:li, value)
      end
    end
  end
end
