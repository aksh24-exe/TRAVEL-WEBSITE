# frozen_string_literal: true

# =============================================================================
# Spec to verify that school settings are merged (not replaced) on update
# and that generate_learner_invoices is properly permitted and preserved.
# =============================================================================
#
# Add this spec to your existing schools_controller_spec.rb or run it
# independently to validate the fix.

require "rails_helper"

RSpec.describe "Admin::SchoolsController - Settings Merge", type: :controller do
  describe "PATCH #update" do
    let(:school) do
      create(:school, settings: {
        title: "Original Title",
        description: "Original Description",
        favicon_url: "https://example.com/favicon.ico",
        logo_url: "https://example.com/logo.png",
        generate_learner_invoices: 1
      }.to_json)
    end

    context "when updating settings without generate_learner_invoices in the payload" do
      let(:update_params) do
        {
          id: school.id,
          school: {
            settings: {
              title: "Updated Title",
              description: "Updated Description",
              favicon_url: nil,
              logo_url: nil
            }.to_json
          }
        }
      end

      it "preserves generate_learner_invoices in settings" do
        patch :update, params: update_params

        school.reload
        updated_settings = JSON.parse(school.settings)

        expect(updated_settings["generate_learner_invoices"]).to eq(1)
        expect(updated_settings["title"]).to eq("Updated Title")
        expect(updated_settings["description"]).to eq("Updated Description")
      end

      it "does not lose any existing settings keys" do
        original_settings = JSON.parse(school.settings)
        original_keys = original_settings.keys

        patch :update, params: update_params

        school.reload
        updated_settings = JSON.parse(school.settings)

        original_keys.each do |key|
          expect(updated_settings).to have_key(key),
            "Expected settings to still contain '#{key}' but it was lost"
        end
      end
    end

    context "when generate_learner_invoices is sent as a separate permitted param" do
      # This tests FIX 1: generate_learner_invoices should no longer be
      # "Unpermitted parameter" after adding it to school_params
      let(:update_params) do
        {
          id: school.id,
          school: {
            generate_learner_invoices: 1,
            settings: {
              title: "Updated Title",
              description: "Updated Description",
              favicon_url: nil,
              logo_url: nil
            }.to_json
          }
        }
      end

      it "does not log an Unpermitted parameter warning" do
        # After adding :generate_learner_invoices to school_params permit list,
        # this parameter should pass through without warnings
        expect(Rails.logger).not_to receive(:warn).with(/Unpermitted parameter.*generate_learner_invoices/)
        patch :update, params: update_params
      end

      it "preserves generate_learner_invoices in the merged settings" do
        patch :update, params: update_params

        school.reload
        updated_settings = JSON.parse(school.settings)

        expect(updated_settings["generate_learner_invoices"]).to eq(1)
      end
    end

    context "when explicitly updating generate_learner_invoices to 0" do
      let(:update_params) do
        {
          id: school.id,
          school: {
            settings: {
              title: "New Title",
              generate_learner_invoices: 0
            }.to_json
          }
        }
      end

      it "allows explicit updates to generate_learner_invoices" do
        patch :update, params: update_params

        school.reload
        updated_settings = JSON.parse(school.settings)

        expect(updated_settings["generate_learner_invoices"]).to eq(0)
        expect(updated_settings["title"]).to eq("New Title")
      end
    end

    context "when updating non-settings attributes only" do
      let(:update_params) do
        {
          id: school.id,
          school: {
            name: "Updated School Name"
          }
        }
      end

      it "does not modify settings at all" do
        original_settings = school.settings

        patch :update, params: update_params

        school.reload
        expect(school.settings).to eq(original_settings)
      end
    end
  end
end
