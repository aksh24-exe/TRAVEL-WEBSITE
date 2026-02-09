# frozen_string_literal: true

# =============================================================================
# Spec to verify that school settings are merged (not replaced) on update
# and that generate_learner_invoices is preserved.
# =============================================================================

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

    context "when updating title/description without generate_learner_invoices" do
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
        original_keys = JSON.parse(school.settings).keys

        patch :update, params: update_params

        school.reload
        updated_settings = JSON.parse(school.settings)

        original_keys.each do |key|
          expect(updated_settings).to have_key(key),
            "Expected settings to still contain '#{key}' but it was lost"
        end
      end
    end

    context "when generate_learner_invoices is sent as a separate param" do
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

      it "injects generate_learner_invoices into the merged settings" do
        patch :update, params: update_params

        school.reload
        updated_settings = JSON.parse(school.settings)

        expect(updated_settings["generate_learner_invoices"]).to eq(1)
        expect(updated_settings["title"]).to eq("Updated Title")
      end
    end

    context "when explicitly disabling generate_learner_invoices" do
      let(:update_params) do
        {
          id: school.id,
          school: {
            generate_learner_invoices: 0,
            settings: {
              title: "New Title"
            }.to_json
          }
        }
      end

      it "allows turning off generate_learner_invoices" do
        patch :update, params: update_params

        school.reload
        updated_settings = JSON.parse(school.settings)

        expect(updated_settings["generate_learner_invoices"]).to eq(0)
        expect(updated_settings["title"]).to eq("New Title")
        # Other existing keys still preserved
        expect(updated_settings["description"]).to eq("Original Description")
      end
    end

    context "when updating non-settings attributes only" do
      let(:update_params) do
        {
          id: school.id,
          school: { name: "Updated School Name" }
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
