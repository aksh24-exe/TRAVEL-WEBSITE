# frozen_string_literal: true

# =============================================================================
# FILE: app/controllers/admin/schools_controller.rb
# =============================================================================
#
# BUG: School Settings Invoice Generation Lost On Update
#
# SYMPTOM:
# --------
# When updating school settings (title, description, etc.), the
# `generate_learner_invoices` key is silently dropped from the settings JSON.
# The user has to manually re-enable it after every settings update.
#
# Log evidence:
#   Unpermitted parameter: :generate_learner_invoices. Context: {  }
#   UPDATE schools SET settings = '{"title":"akshat123","description":"aksaht123",
#     "favicon_url":null,"logo_url":null}' WHERE id = 191393
#   => generate_learner_invoices is GONE
#
# ROOT CAUSE:
# -----------
# 1. The frontend sends `generate_learner_invoices` as a SEPARATE parameter
#    under `school` (i.e., params[:school][:generate_learner_invoices]), NOT
#    inside the `settings` JSON string.
#
# 2. `generate_learner_invoices` is NOT in the `school_params` permit list,
#    so Rails strong parameters silently filters it out:
#      => "Unpermitted parameter: :generate_learner_invoices"
#
# 3. The `settings` JSON is built from form fields (title, description,
#    favicon_url, logo_url) WITHOUT `generate_learner_invoices` (since it
#    was filtered out in step 2).
#
# 4. The entire `settings` column is replaced with this incomplete JSON,
#    losing `generate_learner_invoices` and any other keys not in the form.
#
# FIX (two changes needed):
# -------------------------
# CHANGE 1: Add :generate_learner_invoices to the permit list in school_params
# CHANGE 2: In the update action, merge incoming settings with existing
#            settings so that keys not in the current form are preserved.
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
#     params.require(:school).permit(:name, :description, :settings,
#       :currency_type, :time_zone, :video_quality,
#       :email_verification_days, :access_on_multiple_devices, :language,
#       :logo_file_name, :favicon_file_name, :white_labled,
#       :fb_link, :twitter_link, :linkedin_link, :gplus_link,
#       :youtube_link, :android_link, :ios_link,
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
#     update_params = school_params
#
#     # CHANGE 2: Merge incoming settings with existing settings so that
#     # keys not present in the current request (e.g., generate_learner_invoices
#     # when it was not sent, or any other setting stored in the JSON) are
#     # preserved from the database.
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
#   # This prevents existing keys from being lost when only a subset of
#   # settings is sent from the frontend.
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
#   # CHANGE 1: Added :generate_learner_invoices to the permit list.
#   # Without this, Rails strong parameters silently drops it, causing:
#   #   "Unpermitted parameter: :generate_learner_invoices"
#   def school_params
#     params.require(:school).permit(:name, :description, :settings,
#       :currency_type, :time_zone, :video_quality,
#       :email_verification_days, :access_on_multiple_devices, :language,
#       :logo_file_name, :favicon_file_name, :white_labled,
#       :fb_link, :twitter_link, :linkedin_link, :gplus_link,
#       :youtube_link, :android_link, :ios_link,
#       :is_widgets_enabled, :is_otp_enabled, :tax,
#       :is_billing_address_enabled, :is_shipping_address_enabled,
#       :is_support_enabled, :is_receipt_selected, :telegram_link,
#       :fps_cert_url, :instagram_link,
#       :generate_learner_invoices,                    # <-- ADDED
#       pricing_model_attributes: [:pricing_model])
#   end
