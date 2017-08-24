# Subclass of JsonFile that accepts a filename that represents a UMM form layout
class UmmJsonForm < JsonFile
  # The UmmJsonSchema object this layout is representing
  attr_accessor :schema

  # The object that will populate the elements of form displayed
  attr_accessor :object

  # List of errors after validating the stored object
  attr_accessor :errors

  # Options hash for providing arbitrary values to the form
  attr_accessor :options

  def initialize(form_filename, schema, object, options = {})
    super(form_filename)

    @schema = schema
    @object = object
    @options = options

    # Validate the provided object and set @errors
    validate if options.fetch('validate', true)
  end

  # Retrieve all the forms from the json file
  def forms
    @forms ||= parsed_json.fetch('forms', []).map { |form_json| UmmForm.new(form_json, self, schema, options) }
  end

  # Retrieve a form from the json file by the id
  #
  # ==== Attributes
  #
  # * +id+ - The id of the form to retrieve from +parsed_json+
  def get_form(id)
    forms.find { |form| form['id'] == id }
  end

  # Retrieve the index of the provided form id
  #
  # ==== Attributes
  #
  # * +id+ - The id of the form to retrieve the id from +parsed_json+
  def get_form_index(id)
    forms.index { |form| form['id'] == id }
  end

  # Return the form that appears after the provided id
  #
  # ==== Attributes
  #
  # * +id+ - The id of the form in which you'd like the form that follows (by index)
  def next_form(id)
    next_index = get_form_index(id) + 1

    forms[(next_index > (forms.size - 1)) ? 0 : next_index]
  end

  # Return the form that appears before the provided id
  #
  # ==== Attributes
  #
  # * +id+ - The id of the form in which you'd like the form that preceeds (by index)
  def previous_form(id)
    previous_index = get_form_index(id) - 1

    forms[(previous_index < 0) ? (forms.size - 1) : previous_index]
  end

  # Gets the keys that are relevant to the UMM object as an array from
  # a provided key e.g. 'Parent/items/properties/Field' => ['Parent', 'Field']
  def element_path_for_object(key, ignore_keys: %w(items properties index_id))
    (key.split('/') - ignore_keys).reject(&:blank?)
  end

  # Sanitizes data provided from a form in preparation for storage in the database
  #
  # ==== Attributes
  #
  # * +input+ - Form data submitted the user
  def sanitize_form_input(input, form_id, current_value = {})
    Rails.logger.debug "Before Sanitization: #{input.inspect}"

    # Convert ruby style form element names (example_string) to UMM preferred PascalCase
    input['draft'] = input.fetch('draft', {}).to_camel_keys

    Rails.logger.debug "After CamelKeys: #{input.inspect}"

    Rails.logger.debug "Before setting defaults: #{input['draft'].inspect}"

    input['draft'] = set_defaults(input['draft'], form_id)

    Rails.logger.debug "After setting defaults: #{input['draft'].inspect}"

    unless current_value.blank?
      Rails.logger.debug "A Current Value provided, merging input into: #{current_value.inspect}"

      input['draft'] = current_value.deep_merge(input['draft'])

      Rails.logger.debug "After Deep Merge: #{input['draft'].inspect}"
    end

    # Remove / Ignore empty values submitted by the user. This method returns nil
    # on a completely empty element but for our purposes we need an empty hash
    input['draft'] = compact_blank(input['draft']) || {}

    Rails.logger.debug "After Removing Blanks: #{input.inspect}"

    unless input['draft'].empty?
      # Convert fields that have specific types to their appropriate format
      convert_values_by_type(input['draft'], input['draft'])

      Rails.logger.debug "After Type Conversions: #{input.inspect}"

      # Convert nested arrays from the html form to arrays of hashes
      input['draft'] = convert_to_arrays(input['draft'])
    end

    Rails.logger.debug "After Sanitization: #{input.inspect}"

    input
  end

  # Sets default values for those not present in the fragment that are part of the supplied form
  #
  # ==== Attributes
  #
  # * +fragment+ - JSON (user input) fragment to investigate
  # * +form_id+ - The form submitted
  def set_defaults(fragment, form_id)
    form = get_form(form_id || forms.first.parsed_json['id'])

    form.elements.each do |form_element|
      fragment[form_element.schema_fragment['key']] ||= form_element.default_value
    end

    fragment
  end

  # Manipulates the provided input updating values to represent their native format
  #
  # ==== Attributes
  #
  # * +input+ - Form data submitted the user
  # * +fragment+ - JSON (user input) fragment to investigate
  # * +key+ - They key representing the current location in the hash
  def convert_values_by_type(input, fragment, key = nil)
    fragment.each do |input_key, element|
      # Compile a nested key based on the recursion level
      new_key = [key, input_key].reject(&:blank?).join('/')

      # Keep diggin'
      convert_values_by_type(input, element, new_key) if element.is_a?(Hash)

      # Break the path out into parts for reconstruction
      element_path_as_array = element_path_for_object(new_key)

      # Pull out the key's leaf, we'll use it set the value below
      key_leaf = element_path_as_array.last

      # Remove the key_leaf so we don't navigate passed it below when we're setting the new value
      element_path_as_array.delete(key_leaf)

      # Update the value in the input with the correct object type
      element_path_as_array.reduce(input) { |a, e| a[e] }[key_leaf] = convert_key_to_type(element, schema.element_type(new_key))
    end
  end

  # Attempt to convert the provided input into the specified type
  #
  # ==== Attributes
  #
  # * +value+ - The value to convert to the specified type
  # * +type+ - The type to convert the value to
  def convert_key_to_type(value, type)
    Rails.logger.debug "Convert `#{value}` to a #{type}"

    # Booleans
    return (value.casecmp('true') >= 0 ? true : false) if type == 'boolean'

    # Numbers
    return UmmUtilities.convert_to_number(value) if type == 'number'

    # Integers
    return UmmUtilities.convert_to_integer(value) if type == 'integer'

    # Anything else, return untouched
    value
  rescue => e
    Rails.logger.debug "Error converting `#{value}` to a #{type}: #{e.message}"

    # On any failure, just return the provided value
    value
  end

  # Convert hashes that use integer based keys to array of hashes
  # {'0' => {'id' => 123'}} to [{'id' => '123'}]
  #
  # ==== Attributes
  #
  # * +object+ - An object to convert
  def convert_to_arrays(object)
    case object
    when Hash
      keys = object.keys
      if keys.first =~ /\d+/
        object = object.map { |_key, value| value }
        object.each do |value|
          convert_to_arrays(value)
        end
      else
        object.each do |key, value|
          object[key] = convert_to_arrays(value)
        end
      end
    when Array
      object.each do |value|
        convert_to_arrays(value)
      end
    end
    object
  end

  # Removes empty values from the object
  # ==== Attributes
  #
  # * +node+ - Node to examine for empty values
  def compact_blank(node)
    return node.map { |n| compact_blank(n) }.compact.presence if node.is_a?(Array)
    return node if node == false
    return node.presence unless node.is_a?(Hash)
    result = {}
    node.each do |k, v|
      result[k] = compact_blank(v)
    end
    result = result.compact
    result.compact.presence
  end

  # Run the schema and object through JSON Validator and store the results
  def validate
    @errors ||= JSON::Validator.fully_validate(schema.parsed_json, object, errors_as_objects: true)
  end

  # Returns a list of errors returned from the JSON schema validator
  #
  # ==== Attributes
  #
  # * +ignore_required_fields+ - Whether or not to ignore validations that refer to required fields
  def invalid_keys(ignore_required_fields: true)
    validation_errors = ignore_required_fields ? errors.reject { |error| error[:failed_attribute] == 'Required' && error[:fragment] == '#/' } : errors

    required_fields = validation_errors.map do |e|
      full_key = e[:message].scan(/'([^']+)'/).flatten.map { |capture| capture.gsub('#/', '') }.reject(&:blank?).join('/')

      # If were dealing with a multi item element we only need to validate the top level key
      if full_key =~ /\d+/
        full_key[/[^\d]+/].split('/').first
      else
        full_key
      end
    end

    required_fields.reject(&:blank?).uniq
  end

  # Determine whether or not a provided key is invalid
  #
  # ==== Attributes
  #
  # * +key+ - Key to check validity on
  # * +ignore_required_fields+ - Whether or not to ignore validations that refer to required fields
  # * +ignore_keys+ - Keys to ignore when comparing to those returned from the JSON Schema validator
  def invalid?(key, ignore_required_fields: true, ignore_keys: %w(items properties index_id))
    key = element_path_for_object(key, ignore_keys: ignore_keys).join('/')
    invalid_keys(ignore_required_fields: ignore_required_fields).include?(key)
  end
end
