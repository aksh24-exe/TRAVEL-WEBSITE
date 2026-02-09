# frozen_string_literal: true

# =============================================================================
# FILE: app/controllers/admin/schools_controller.rb
# =============================================================================
#
# This file shows the EXACT changes needed in the schools controller to fix
# the settings overwrite bug.
#
# CHANGE SUMMARY:
# - In the `update` action, merge incoming settings with existing settings
#   before calling @school.update, so that existing keys like
#   `generate_learner_invoices` are not lost.
#
# =============================================================================

# BEFORE (buggy):
# ----------------
#
#   def update
#     @school = School.find(params[:id])
#     if @school.update(school_params)
#       render json: { success: true }
#     else
#       render json: { errors: @school.errors }, status: :unprocessable_entity
#     end
#   end
#
#   private
#
#   def school_params
#     params.require(:school).permit(:name, :description, :settings, :currency_type,
#       :time_zone, :video_quality, :email_verification_days,
#       :access_on_multiple_devices, :language, :logo_file_name,
#       :favicon_file_name, :white_labled, :fb_link, :twitter_link,
#       :linkedin_link, :gplus_link, :youtube_link, :android_link, :ios_link,
#       :is_widgets_enabled, :is_otp_enabled, :tax,
#       :is_billing_address_enabled, :is_shipping_address_enabled,
#       :is_support_enabled, :is_receipt_selected, :telegram_link,
#       :fps_cert_url, :instagram_link,
#       pricing_model_attributes: [:pricing_model])
#   end

# AFTER (fixed):
# ---------------
#
#   def update
#     @school = School.find(params[:id])
#
#     # Merge incoming settings with existing settings to preserve all keys
#     update_params = school_params
#     if update_params[:settings].present?
#       update_params[:settings] = merged_settings(@school, update_params[:settings])
#     end
#
#     if @school.update(update_params)
#       render json: { success: true }
#     else
#       render json: { errors: @school.errors }, status: :unprocessable_entity
#     end
#   end
#
#   private
#
#   # Merges incoming settings JSON with the school's existing settings.
#   # This prevents existing keys (e.g., generate_learner_invoices) from being
#   # lost when only a subset of settings is sent from the frontend.
#   #
#   # @param school [School] the school being updated
#   # @param incoming_settings [String, Hash] the settings from the request
#   # @return [String] JSON string with merged settings
#   def merged_settings(school, incoming_settings)
#     existing = school.settings
#     existing = existing.is_a?(String) ? JSON.parse(existing) : (existing || {})
#     incoming = incoming_settings.is_a?(String) ? JSON.parse(incoming_settings) : (incoming_settings || {})
#
#     existing.merge(incoming).to_json
#   rescue JSON::ParserError
#     incoming_settings
#   end
#
#   def school_params
#     params.require(:school).permit(:name, :description, :settings, :currency_type,
#       :time_zone, :video_quality, :email_verification_days,
#       :access_on_multiple_devices, :language, :logo_file_name,
#       :favicon_file_name, :white_labled, :fb_link, :twitter_link,
#       :linkedin_link, :gplus_link, :youtube_link, :android_link, :ios_link,
#       :is_widgets_enabled, :is_otp_enabled, :tax,
#       :is_billing_address_enabled, :is_shipping_address_enabled,
#       :is_support_enabled, :is_receipt_selected, :telegram_link,
#       :fps_cert_url, :instagram_link,
#       pricing_model_attributes: [:pricing_model])
#   end
