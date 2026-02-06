# frozen_string_literal: true

class Types::Users::TransactionType < Types::BaseObject

  BASE_TAX = 18.0

  ENUM_ATTRIBUTES = {
    user_consent_status: Enums::Users::ConsentStatus
  }.freeze

  IDENTIFIER_FIELDS = {
    email: "Deleted Learner"
  }.freeze

  USER_ADDRESS_FIELDS = %w[street_address1 street_address2 city state country pincode company gstin].freeze

  include BaseHelper

  field :amount, String, null: true
  field :billing_address, String, null: true
  field :created_at, GraphQL::Types::ISO8601DateTime, null: true
  field :dob, GraphQL::Types::ISO8601DateTime, null: true
  field :email, String, null: true
  field :home_currency_amount, String, null: true
  field :id, ID, null: false
  field :invoice_file_name, String, null: true
  field :invoice_id, String, null: true
  field :mobile, String, null: true
  field :name, String, null: true
  field :pan, String, null: true
  field :pan_status, Enums::PanStatusEnums, null: true
  field :place_of_supply, String, null: true
  field :price, String, null: true
  field :shipping_address, String, null: true
  field :tax_amount, String, null: true
  field :tax_applied, String, null: true
  field :title, String, null: true
  field :user_consent_status, String, null: true
  field :user_id, ID, null: true

  ENUM_ATTRIBUTES.each do |enum_attr, enum_class|
    define_method enum_attr.to_s do
      value = object.public_send(enum_attr)
      fetch_enum_value(enum_class: enum_class, key: value)
    end
  end

  IDENTIFIER_FIELDS.each do |name, placeholder|
    define_method name.to_s do
      object.user_id.blank? ? placeholder : object.send(name)
    end
  end

  def address(loader:, address:)
    raw_address = address.as_json.slice(*USER_ADDRESS_FIELDS)
    raw_address.symbolize_keys!
    country = JSON.parse(raw_address.delete(:country), symbolize_names: true)[:value] if address.country.present?
    state = JSON.parse(raw_address.delete(:state), symbolize_names: true)[:value] if address.state.present?
    address_in_sentence = (raw_address.values + [state, country]).delete_if(&:blank?).join(", ")
    loader.call(address.user_id, address_in_sentence)
  end

  def billing_address
    BatchLoader::GraphQL.for(object.user_id).batch do |user_ids, loader|
      Address.select(USER_ADDRESS_FIELDS + %w[school_id user_id address_type]).where(school_id: object.school_id, user_id: user_ids, address_type: Address::BILLING_ADDRESS).each do |address|
        address(loader: loader, address: address)
      end
    end
  end

  def shipping_address
    BatchLoader::GraphQL.for(object.user_id).batch do |user_ids, loader|
      Address.select(USER_ADDRESS_FIELDS + %w[school_id user_id address_type]).where(school_id: object.school_id, user_id: user_ids, address_type: Address::SHIPPING_ADDRESS).each do |address|
        address(loader: loader, address: address)
      end
    end
  end

  def place_of_supply
    BatchLoader::GraphQL.for(object.user_id).batch do |user_ids, loader|
      Address.select(USER_ADDRESS_FIELDS + %w[school_id user_id address_type]).where(school_id: object.school_id, user_id: user_ids, address_type: Address::BILLING_ADDRESS).each do |address|
        state = JSON.parse(address.state, symbolize_names: true)[:value] if address.state.present?
        loader.call(address.user_id, state)
      end
    end
  end

  # calculating percentage of tax applied on the particular order
  def tax_applied
    return nil unless object.tax_amount.to_f.positive?
    tax_percent = ((object.tax_amount.to_f / (object.amount - object.tax_amount)) * 100)
    tax_label = object.is_sgst_cgst_order == 0 ? "IGST" : "SGST + CGST"
    tax_value = (BASE_TAX - tax_percent).abs < 1 ? BASE_TAX : tax_percent.round
    "#{tax_value}% (#{tax_label})"
  end
end
