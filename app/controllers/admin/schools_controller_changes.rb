# frozen_string_literal: true

# =============================================================================
# FILE: app/controllers/admin/schools_controller.rb
# =============================================================================
#
# BUG: generate_learner_invoices Lost When Updating School Settings
#
# SYMPTOM (from logs):
#   Unpermitted parameter: :generate_learner_invoices
#   UPDATE schools SET settings = '{"title":"akshat123","description":"aksaht123",
#     "favicon_url":null,"logo_url":null}' WHERE id = 191393
#   => generate_learner_invoices is GONE from settings JSON
#
# ROOT CAUSE:
#   1. `generate_learner_invoices` lives INSIDE the `settings` JSON column,
#      not as its own database column.
#   2. The frontend sends `school[settings]` as a JSON string containing
#      only {title, description, favicon_url, logo_url}.
#   3. The frontend ALSO sends `school[generate_learner_invoices]` as a
#      separate param, but it's NOT in the permit list, so it's dropped.
#   4. `assign_attributes(school_params...)` replaces @school.settings
#      with the incomplete JSON, losing generate_learner_invoices.
#   5. Even if we added generate_learner_invoices to the permit list,
#      assign_attributes would try to set it as a direct column (which
#      doesn't exist) rather than merging it into the settings JSON.
#
# FIX:
#   Before assign_attributes, capture the existing settings.
#   After assign_attributes, merge the old settings with the new settings.
#   Also extract generate_learner_invoices from params and inject it
#   into the merged settings if present.
#
# =============================================================================

# BEFORE (buggy):
# ----------------
#
#   def update
#     authorize School, policy_class: ApplicationPolicy
#     kycs = Kyc.where(school_id: @school.id, is_default: true).first
#     if params[:school][:tax] && params[:school][:tax].to_i > School::NO_TAX && !kycs
#       send_client_error(412, "Kindly provide the GSTIN details...")
#       return
#     end
#     school_json = {}
#     @school.assign_attributes(school_params.except(*School::SOCIAL_MEDIA_LINKS))
#     # ^^^ BUG: This replaces @school.settings with incomplete JSON,
#     #          losing generate_learner_invoices and any other keys
#     #          not sent by the frontend form.
#     ...
#   end

# AFTER (fixed):
# ---------------
#
#   def update
#     authorize School, policy_class: ApplicationPolicy
#     kycs = Kyc.where(school_id: @school.id, is_default: true).first
#     if params[:school][:tax] && params[:school][:tax].to_i > School::NO_TAX && !kycs
#       send_client_error(412, "Kindly provide the GSTIN details to enable this feature. You can provide the GSTIN details from Billing address form available at Bills page.")
#       return
#     end
#     school_json = {}
#
#     # --- FIX START: Preserve existing settings before assign_attributes ---
#     existing_settings = parse_settings_json(@school.settings)
#     # --- FIX END ---
#
#     @school.assign_attributes(school_params.except(*School::SOCIAL_MEDIA_LINKS))
#
#     # --- FIX START: Merge new settings with existing to preserve all keys ---
#     if school_params[:settings].present?
#       new_settings = parse_settings_json(@school.settings)
#       merged = existing_settings.merge(new_settings)
#
#       # Also inject generate_learner_invoices from params if sent separately
#       # (frontend sends it as school[generate_learner_invoices], not inside settings JSON)
#       unless params.dig(:school, :generate_learner_invoices).nil?
#         merged["generate_learner_invoices"] = params.dig(:school, :generate_learner_invoices).to_i
#       end
#
#       @school.settings = merged.to_json
#     end
#     # --- FIX END ---
#
#     @school.set_social_media_links_data(school_params.as_json(only: School::SOCIAL_MEDIA_LINKS).symbolize_keys!)
#     social_links = @school.social_links
#     school = @school.as_json(except: %i[sub_domain main_domain social_links]).merge!(social_links)
#     @school.school_attribute&.is_fast_checkout_enabled = params[:is_fast_checkout_enabled] if params[:is_fast_checkout_enabled].present?
#     @school.school_attribute&.is_device_restriction_enabled = params.dig("school", "is_device_restriction_enabled") unless params.dig("school", "is_device_restriction_enabled").nil?
#     @school.school_attribute&.no_of_registered_devices = params.dig("school", "no_of_registered_devices") unless params.dig("school", "no_of_registered_devices").nil?
#     @school.school_attribute&.is_parallel_login_restriction_enabled = params.dig("school", "is_parallel_login_restriction_enabled") unless params.dig("school", "is_parallel_login_restriction_enabled").nil?
#     @school.school_attribute&.onboarding_config = params[:onboarding_config] if params[:onboarding_config].present?
#     return render status: :bad_request, json: { message: @school.school_attribute.errors.messages.values[0][0] } unless @school.school_attribute&.save
#
#     school_json[:is_fast_checkout_enabled] = @school.school_attribute&.is_fast_checkout_enabled
#     school_json[:is_device_restriction_enabled] = @school.school_attribute&.is_device_restriction_enabled
#     school_json[:is_parallel_login_restriction_enabled] = @school.school_attribute&.is_parallel_login_restriction_enabled
#     school_json[:no_of_registered_devices] = @school.school_attribute&.no_of_registered_devices
#
#     if @school.save
#       school_json[:pricing_model] = @school&.pricing_model&.pricing_model
#       school_json.merge!(school)
#       render status: :ok, json: school_json
#     else
#       render status: :bad_request, json: { message: @school.errors.messages.values[0][0] }
#     end
#   end
#
#   private
#
#   # Safely parses a settings value (String or Hash) into a Hash.
#   def parse_settings_json(value)
#     return {} if value.blank?
#
#     case value
#     when String then JSON.parse(value)
#     when Hash   then value
#     else {}
#     end
#   rescue JSON::ParserError
#     {}
#   end
