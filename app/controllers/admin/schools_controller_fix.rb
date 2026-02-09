# frozen_string_literal: true

# =============================================================================
# FIX: School Settings Invoice Generation Bug
# =============================================================================
#
# Bug: When updating school settings (title, description) the entire `settings`
# JSON column is replaced, losing `generate_learner_invoices` and any other
# keys not in the frontend form.
#
# Cause: assign_attributes replaces @school.settings with the incoming JSON.
# The frontend only sends {title, description, favicon_url, logo_url} in the
# settings JSON. generate_learner_invoices is sent as a separate param but
# is not permitted and not a direct column, so it's silently dropped.
#
# =============================================================================
# EXACT CHANGES TO MAKE IN: app/controllers/admin/schools_controller.rb
# =============================================================================
#
# STEP 1: Add this private helper method to the controller:
# ----------------------------------------------------------
#
#   private
#
#   def parse_settings_json(value)
#     return {} if value.blank?
#     case value
#     when String then JSON.parse(value)
#     when Hash   then value
#     else {}
#     end
#   rescue JSON::ParserError
#     {}
#   end
#
#
# STEP 2: In the `update` action, add the merge logic around assign_attributes:
# -------------------------------------------------------------------------------
#
# Find this line:
#
#     @school.assign_attributes(school_params.except(*School::SOCIAL_MEDIA_LINKS))
#
# Replace it with:
#
#     existing_settings = parse_settings_json(@school.settings)
#     @school.assign_attributes(school_params.except(*School::SOCIAL_MEDIA_LINKS))
#     if school_params[:settings].present?
#       new_settings = parse_settings_json(@school.settings)
#       merged = existing_settings.merge(new_settings)
#       unless params.dig(:school, :generate_learner_invoices).nil?
#         merged["generate_learner_invoices"] = params.dig(:school, :generate_learner_invoices).to_i
#       end
#       @school.settings = merged.to_json
#     end
#
#
# That's it. Here's what each line does:
#
#   existing_settings = parse_settings_json(@school.settings)
#     => Capture the CURRENT settings from the DB before they get overwritten.
#        e.g. {"title":"old","generate_learner_invoices":1}
#
#   @school.assign_attributes(school_params.except(*School::SOCIAL_MEDIA_LINKS))
#     => This overwrites @school.settings with the incomplete incoming JSON.
#        e.g. {"title":"new","description":"desc","favicon_url":null,"logo_url":null}
#
#   new_settings = parse_settings_json(@school.settings)
#     => Parse the newly assigned (incomplete) settings.
#
#   merged = existing_settings.merge(new_settings)
#     => Hash#merge keeps all keys from existing_settings and overwrites
#        with keys from new_settings. Result:
#        {"title":"new","generate_learner_invoices":1,"description":"desc",
#         "favicon_url":null,"logo_url":null}
#
#   unless params.dig(:school, :generate_learner_invoices).nil?
#     merged["generate_learner_invoices"] = params.dig(:school, :generate_learner_invoices).to_i
#   end
#     => If generate_learner_invoices was also sent as a separate param
#        (which triggers the "Unpermitted parameter" warning), pick it up
#        directly from params and inject into merged settings.
#        This handles the case where the user explicitly toggles it.
#
#   @school.settings = merged.to_json
#     => Write the complete merged JSON back to @school.settings.
#        Now when @school.save runs, nothing is lost.
