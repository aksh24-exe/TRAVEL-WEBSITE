# frozen_string_literal: true

# =============================================================================
# FIX: School Settings Invoice Generation Bug
# =============================================================================
#
# Problem:
# --------
# When updating school settings (e.g., title, description) through the admin
# schools controller, the `generate_learner_invoices` setting is lost because:
#
#   1. `generate_learner_invoices` is sent as a separate parameter under
#      `school` (school[generate_learner_invoices]) by the frontend.
#
#   2. It is NOT in the `school_params` permit list, so Rails strong
#      parameters silently drops it:
#        => "Unpermitted parameter: :generate_learner_invoices"
#
#   3. The `settings` JSON column is rebuilt from only the permitted form
#      fields (title, description, favicon_url, logo_url), completely
#      replacing the old JSON and losing generate_learner_invoices.
#
# Two fixes are needed:
# ---------------------
#
#   FIX 1: Add :generate_learner_invoices to school_params permit list
#          This stops the "Unpermitted parameter" warning and allows the
#          value to pass through when explicitly sent from the frontend.
#
#   FIX 2: Merge incoming settings with existing settings in the update
#          action, so keys not present in the current form submission
#          are preserved from the database. This is a safety net that
#          protects against ANY settings key being accidentally lost,
#          not just generate_learner_invoices.
#
# =============================================================================

# =============================================================================
# FIX 1: Update school_params permit list
# =============================================================================
#
# In app/controllers/admin/schools_controller.rb, add
# :generate_learner_invoices to the permit call:
#
#   def school_params
#     params.require(:school).permit(
#       :name, :description, :settings, :currency_type, :time_zone,
#       :video_quality, :email_verification_days, :access_on_multiple_devices,
#       :language, :logo_file_name, :favicon_file_name, :white_labled,
#       :fb_link, :twitter_link, :linkedin_link, :gplus_link, :youtube_link,
#       :android_link, :ios_link, :is_widgets_enabled, :is_otp_enabled, :tax,
#       :is_billing_address_enabled, :is_shipping_address_enabled,
#       :is_support_enabled, :is_receipt_selected, :telegram_link,
#       :fps_cert_url, :instagram_link,
#       :generate_learner_invoices,                    # <-- ADD THIS
#       pricing_model_attributes: [:pricing_model]
#     )
#   end

# =============================================================================
# FIX 2: Merge settings in the update action
# =============================================================================
#
# In the `update` action, merge incoming settings with existing ones:
#
#   def update
#     @school = School.find(params[:id])
#
#     update_params = school_params
#
#     # Merge incoming settings with existing settings to preserve all keys
#     if update_params[:settings].present?
#       update_params[:settings] = merged_settings(@school, update_params[:settings])
#     end
#
#     if @school.update(update_params)
#       # success handling
#     else
#       # error handling
#     end
#   end
#
#   private
#
#   def merged_settings(school, incoming_settings)
#     existing = parse_settings(school.settings)
#     incoming = parse_settings(incoming_settings)
#
#     existing.merge(incoming).to_json
#   rescue JSON::ParserError
#     incoming_settings
#   end
#
#   def parse_settings(value)
#     return {} if value.blank?
#
#     case value
#     when String then JSON.parse(value)
#     when Hash   then value.to_h
#     else {}
#     end
#   end

# =============================================================================
# IMPLEMENTATION: Reusable controller concern
# =============================================================================
#
# Alternatively, extract the merge logic into a concern that can be included
# in any controller that touches school settings:

module Admin
  module SchoolSettingsMerger
    extend ActiveSupport::Concern

    private

    # Merges incoming settings with existing settings to prevent data loss.
    #
    # When the frontend sends only a subset of settings keys (e.g., title
    # and description but not generate_learner_invoices), existing keys in
    # the database are preserved.
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
    # Usage:
    #   def update
    #     @school = School.find(params[:id])
    #     if @school.update(school_params_with_merged_settings(@school))
    #       ...
    #     end
    #   end
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
