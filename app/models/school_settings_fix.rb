# frozen_string_literal: true

# =============================================================================
# ALTERNATIVE: Model-level fix in app/models/school.rb
# =============================================================================
#
# If you prefer the model to handle settings merging automatically instead
# of doing it in the controller, add this callback. This guarantees that
# settings are ALWAYS merged regardless of which controller or service
# updates the school.
#
# NOTE: The controller fix (see schools_controller_fix.rb) is recommended
# because it also handles the separate generate_learner_invoices param.
# If you use this model approach, you still need to handle that param
# in the controller.
# =============================================================================

# class School < ApplicationRecord
#   # ... existing code ...
#
#   before_save :merge_settings_with_existing, if: :settings_changed?
#
#   private
#
#   def merge_settings_with_existing
#     old_settings = parse_json_settings(settings_was)
#     new_settings = parse_json_settings(settings)
#
#     self.settings = old_settings.merge(new_settings).to_json
#   rescue JSON::ParserError => e
#     Rails.logger.error("School#merge_settings_with_existing failed: #{e.message}")
#   end
#
#   def parse_json_settings(value)
#     return {} if value.blank?
#     case value
#     when String then JSON.parse(value)
#     when Hash   then value
#     else {}
#     end
#   end
# end
