# frozen_string_literal: true

# =============================================================================
# FILE: app/models/school.rb (Model-level fix - Alternative to controller fix)
# =============================================================================
#
# This is an ALTERNATIVE approach. Use this if you prefer the model to handle
# settings merging automatically, rather than doing it in the controller.
#
# NOTE: You still need FIX 1 (adding :generate_learner_invoices to the permit
# list in school_params) regardless of whether you use this model fix or the
# controller fix.
#
# Add the following to your School model:
# =============================================================================

# class School < ApplicationRecord
#   # ... existing code ...
#
#   before_save :merge_settings_with_existing, if: :settings_changed?
#
#   private
#
#   # Merges incoming settings with previously stored settings so that
#   # keys not included in the current update (e.g., generate_learner_invoices)
#   # are preserved rather than silently dropped.
#   #
#   # Example:
#   #   DB has:    {"title":"old","generate_learner_invoices":1}
#   #   Incoming:  {"title":"new","description":"desc","favicon_url":null,"logo_url":null}
#   #   Merged:    {"title":"new","generate_learner_invoices":1,"description":"desc","favicon_url":null,"logo_url":null}
#   #
#   def merge_settings_with_existing
#     old_settings = parse_json_settings(settings_was)
#     new_settings = parse_json_settings(settings)
#
#     self.settings = old_settings.merge(new_settings).to_json
#   rescue JSON::ParserError => e
#     Rails.logger.error("School#merge_settings_with_existing failed: #{e.message}")
#     # Keep incoming settings as-is if parsing fails
#   end
#
#   def parse_json_settings(value)
#     return {} if value.blank?
#
#     case value
#     when String then JSON.parse(value)
#     when Hash   then value
#     else {}
#     end
#   end
# end
