# :nodoc:
class ManageMetadataController < ApplicationController
  include ManageMetadataHelper

  protected

  # helper methods used by published record controller methods ensuring a user
  # has the appropriate provider context set
  def set_record_action
    @record_action =  case
                      when request.original_url.include?('edit')
                        'edit'
                      when request.original_url.include?('delete')
                        'delete'
                      when request.original_url.include?('clone')
                        'clone'
                      when request.original_url.include?('revert')
                        'revert'
                      end
  end

  def set_user_permissions
    @user_permissions = if available_provider?(@provider_id)
                          'wrong_provider'
                        else
                          'none'
                        end
  end

  def set_variable
    @concept_id = params[:variable_id] || params[:id]
    @revision_id = params[:revision_id]

    # retrieve the variable metadata with the current umm_var version
    headers = { 'Accept' => "application/#{Rails.configuration.umm_var_version}; charset=utf-8" }
    variable_concept_response = cmr_client.get_concept(@concept_id, token, headers, @revision_id)

    @variable = if variable_concept_response.success?
                  variable_concept_response.body
                else
                  Rails.logger.error("Error retrieving concept for Variable #{@concept_id} in `set_variable`: #{variable_concept_response.inspect}")
                  {}
                end

    set_variable_information
  end

  def set_variable_information
    # search for variable by concept id to get the native_id and provider_id
    # if the variable is not found, try again because CMR might be a little slow to index if it is a newly published record
    attempts = 0
    while attempts < 20
      variables_search_response = cmr_client.get_variables(concept_id: @concept_id, all_revisions: true)

      variable_data = if variables_search_response.success?
                        variables_search_response.body.fetch('items', [])
                      else
                        []
                      end
      variable_data.sort! { |a, b| b['meta']['revision-id'] <=> a['meta']['revision-id'] }

      @revisions = variable_data
      latest = variable_data.first
      meta = latest.nil? ? {} : latest.fetch('meta', {})

      @old_revision = !@revision_id.nil? && meta['revision-id'].to_s != @revision_id.to_s ? true : false

      break if latest && !@revision_id
      break if latest && meta.fetch('revision-id', 0) >= @revision_id.to_i && meta['concept-id'] == @concept_id
      attempts += 1
      sleep 0.05
    end

    if latest.blank?
      Rails.logger.error("Error searching for Variable #{@concept_id} in `set_variable_information`: #{variables_search_response.inspect}")
    else
      @provider_id = meta['provider-id']
      @native_id = meta['native-id']
      @num_associated_collections = cmr_client.get_collections_by_post({ variable_concept_id: @concept_id }, token).body.fetch('items', []).size
    end
  end

  def set_service
    @concept_id = params[:service_id] || params[:id]
    @revision_id = params[:revision_id]

    # retrieve the variable metadata with the current umm_var version
    headers = { 'Accept' => "application/#{Rails.configuration.umm_s_version}; charset=utf-8" }
    service_concept_response = cmr_client.get_concept(@concept_id, token, headers, @revision_id)

    @service = if service_concept_response.success?
                  service_concept_response.body
                else
                  Rails.logger.error("Error retrieving concept for Variable #{@concept_id} in `set_service`: #{service_concept_response.inspect}")
                  {}
                end

    set_service_information
  end

  def set_service_information
    # search for service by concept id to get the native_id and provider_id
    # if the service is not found, try again because CMR might be a little slow to index if it is a newly published record
    attempts = 0
    while attempts < 20
      services_search_response = cmr_client.get_services(concept_id: @concept_id, all_revisions: true)

      service_data = if services_search_response.success?
                       services_search_response.body.fetch('items', [])
                     else
                       []
                     end
      service_data.sort! { |a, b| b['meta']['revision-id'] <=> a['meta']['revision-id'] }

      @revisions = service_data
      latest = service_data.first
      meta = latest.nil? ? {} : latest.fetch('meta', {})

      @old_revision = !@revision_id.nil? && meta['revision-id'].to_s != @revision_id.to_s ? true : false

      break if latest && !@revision_id
      break if latest && meta.fetch('revision-id', 0) >= @revision_id.to_i && meta['concept-id'] == @concept_id
      attempts += 1
      sleep 0.05
    end

    if latest.blank?
      Rails.logger.error("Error searching for Service #{@concept_id} in `set_service_information`: #{services_search_response.inspect}")
    else
      @provider_id = meta['provider-id']
      @native_id = meta['native-id']
      @num_associated_collections = cmr_client.get_collections_by_post({ service_concept_id: @concept_id }, token).body.fetch('items', []).size
    end
  end

  def generate_ingest_errors(response)
    errors = response.errors
    request_id = response.cmr_request_header

    if errors.empty?
      [{
        page: nil,
        field: nil,
        error: 'An unknown error caused publishing to fail.',
        request_id: request_id
      }]
    else
      errors.map do |error|
        path = error['path'].nil? ? [nil] : Array.wrap(error['path'])
        error = error['errors'].nil? ? error : error['errors'].first

        # only show the feedback module link if the error is 500
        request_id = nil unless response.status == 500
        {
          field: path.last,
          top_field: path.first,
          page: get_page(path),
          error: error,
          request_id: request_id
        }
      end
    end
  end

  def get_page(fields)
    # for path in generate_ingest_errors
    return nil if fields.nil?
    # for field in generate_show_errors
    if ACQUISITION_INFORMATION_FIELDS.include? fields.first
      'acquisition_information'
    elsif COLLECTION_INFORMATION_FIELDS.include? fields.first
      'collection_information'
    elsif COLLECTION_CITATIONS_FIELDS.include? fields.first
      'collection_citations'
    elsif DATA_IDENTIFICATION_FIELDS.include? fields.first
      'data_identification'
    elsif DESCRIPTIVE_KEYWORDS_FIELDS.include? fields.first
      'descriptive_keywords'
    elsif RELATED_URL_FIELDS.include? fields.first
      'related_urls'
    elsif METADATA_INFORMATION_FIELDS.include? fields.first
      'metadata_information'
    elsif fields.include?('ContactPersons' || 'ContactGroups') # DATA_CONTACTS
      'data_contacts'
    elsif DATA_CENTERS_FIELDS.include? fields.first
      'data_centers'
    elsif SPATIAL_INFORMATION_FIELDS.include? fields.first
      'spatial_information'
    elsif TEMPORAL_INFORMATION_FIELDS.include? fields.first
      'temporal_information'
    end
  end
end
