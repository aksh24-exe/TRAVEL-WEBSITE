# frozen_string_literal: true

# FIX: School Settings Invoice Generation Bug
#
# Problem:
# --------
# When updating school settings (e.g., title, description) through the admin
# schools controller, the entire `settings` JSON column is replaced with only
# the incoming values. This causes previously saved settings like
# `generate_learner_invoices` to be lost (reset to 0/null).
#
# Example of the bug:
#   Before update: settings = {"title":"test", "generate_learner_invoices":1}
#   User updates title to "akshat123"
#   After update:  settings = {"title":"akshat123","description":"aksaht123","favicon_url":null,"logo_url":null}
#   => generate_learner_invoices is LOST
#
# Root Cause:
# -----------
# The `settings` parameter is permitted as a scalar in `school_params`:
#
#   def school_params
#     params.require(:school).permit(:name, :description, :settings, ...)
#   end
#
# When the frontend sends a partial settings hash (e.g., only title/description),
# it completely overwrites the existing settings JSON in the database instead
# of merging with the existing values.
#
# Fix:
# ----
# Merge incoming settings with existing settings before saving. This ensures
# that keys not present in the incoming payload (like `generate_learner_invoices`)
# are preserved from the existing record.
#
# Apply one of the following approaches depending on your codebase structure:

# ============================================================================
# APPROACH 1: Fix in the Controller (Recommended)
# ============================================================================
#
# In the `update` action of your SchoolsController, merge settings before update:
#
#   # app/controllers/admin/schools_controller.rb
#
#   def update
#     @school = School.find(params[:id])
#
#     merged_params = school_params
#
#     # Merge incoming settings with existing settings to preserve keys
#     # like generate_learner_invoices that may not be in the current form
#     if merged_params[:settings].present?
#       merged_params[:settings] = merge_school_settings(@school, merged_params[:settings])
#     end
#
#     if @school.update(merged_params)
#       # success handling
#     else
#       # error handling
#     end
#   end
#
#   private
#
#   def merge_school_settings(school, incoming_settings)
#     existing_settings = school.settings.is_a?(String) ? JSON.parse(school.settings) : (school.settings || {})
#     new_settings = incoming_settings.is_a?(String) ? JSON.parse(incoming_settings) : (incoming_settings || {})
#
#     existing_settings.merge(new_settings).to_json
#   rescue JSON::ParserError
#     incoming_settings
#   end

# ============================================================================
# APPROACH 2: Fix in the Model using a before_save callback
# ============================================================================
#
# If you prefer the model to handle this automatically:
#
#   # app/models/school.rb
#
#   before_save :merge_settings, if: :settings_changed?
#
#   private
#
#   def merge_settings
#     return unless settings_changed?
#
#     old_settings = settings_was.is_a?(String) ? JSON.parse(settings_was) : (settings_was || {})
#     new_settings = settings.is_a?(String) ? JSON.parse(settings) : (settings || {})
#
#     self.settings = old_settings.merge(new_settings).to_json
#   rescue JSON::ParserError
#     # If parsing fails, keep the incoming settings as-is
#   end


# ============================================================================
# IMPLEMENTATION: Controller concern for merging school settings
# ============================================================================

module Admin
  module SchoolSettingsMerger
    extend ActiveSupport::Concern

    private

    # Merges incoming settings with existing settings to prevent data loss.
    #
    # This method ensures that when a subset of settings is sent from the
    # frontend (e.g., only title and description), other existing settings
    # (e.g., generate_learner_invoices) are not overwritten/lost.
    #
    # @param school [School] the school record with existing settings
    # @param incoming_settings [String, Hash] the new settings from params
    # @return [String] merged JSON settings string
    def merge_school_settings(school, incoming_settings)
      existing_settings = parse_settings(school.settings)
      new_settings = parse_settings(incoming_settings)

      existing_settings.merge(new_settings).to_json
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to merge school settings: #{e.message}")
      incoming_settings
    end

    # Safely parses settings from either a JSON string or a Hash.
    #
    # @param settings [String, Hash, nil] settings to parse
    # @return [Hash] parsed settings hash
    def parse_settings(settings)
      return {} if settings.blank?

      case settings
      when String
        JSON.parse(settings)
      when Hash, HashWithIndifferentAccess
        settings.to_h
      else
        {}
      end
    end

    # Processes school_params to merge settings before saving.
    # Call this in your update action instead of using school_params directly.
    #
    # @param school [School] the school record being updated
    # @return [ActionController::Parameters] params with merged settings
    def school_params_with_merged_settings(school)
      merged = school_params
      if merged[:settings].present?
        merged[:settings] = merge_school_settings(school, merged[:settings])
      end
      merged
    end
  end
end
