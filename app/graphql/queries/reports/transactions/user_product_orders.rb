# frozen_string_literal: true

class Queries::Reports::Transactions::UserProductOrders < Queries::BaseQuery

  include BaseHelper

  TRANSACTIONS = 0
  INVOICES = 1

  CUSTOM_FILTER_FIELDS = {
    email: { model: User, dependent_index: :school_id, context_key: :school, context_value: :id },
    name: { model: User, dependent_index: :school_id, context_key: :school, context_value: :id },
    course_type: { model: Course, dependent_index: :school_id, context_key: :school, context_value: :id },
    mobile: { model: User, dependent_index: :school_id, context_key: :school, context_value: :id },
    invoice_id: { model: LearnerInvoice },
    tax_amount: { model: LearnerInvoice },
    country: { model: Address, dependent_index: :school_id, context_key: :school, context_value: :id },
    state: { model: Address, dependent_index: :school_id, context_key: :school, context_value: :id },
    tracking_code: { model: CouponCode, dependent_index: :school_id, context_key: :school, context_value: :id, alias_key: "code"  }
  }.freeze

  # Optimized: removed 18 columns not displayed on frontend
  # Removed: users.profile_photo_file_name, courses.course_type, orders.transaction_status,
  #          orders.transaction_id, orders.payment_type, orders.coupon_code, orders.coupon_amount,
  #          orders.learner_invoice_id, orders.course_id, orders.pg_order_id, orders.pg_reference,
  #          orders.currency_code, orders.product_pricing_id, addresses.state, addresses.country,
  #          orders.consent_page_id, orders.mrp, orders.type_of_payment
  DEFAULT_SELECT_FIELDS = %w[orders.id users.name users.mobile users.pan users.pan_status users.dob users.email courses.title orders.created_at orders.price orders.home_currency_amount orders.user_consent_status].freeze

  # JOINs kept for addresses and coupon_codes because CUSTOM_FILTER_FIELDS uses them for filtering
  DEFAULT_JOIN_QUERY = "left join courses on orders.course_id = courses.id and orders.school_id = courses.school_id left join users on orders.user_id = users.id left join coupon_codes on coupon_codes.id = orders.tracking_id and coupon_codes.school_id = orders.school_id and coupon_codes.coupon_type = #{CouponCode::AFFILIATE_COUPON} left join addresses on addresses.user_id = orders.user_id and addresses.school_id = orders.school_id and addresses.address_type = #{Address::BILLING_ADDRESS}"

  # Optimized: removed "coupon_codes.code as tracking_code" (not displayed on frontend)
  ALIAS_FIELDS = ["users.id as user_id", "orders.school_id as school_id"].freeze
  extras [:lookahead]

  type Types::Users::TransactionType.connection_type, null: true

  argument :end_date, GraphQL::Types::ISO8601Date, required: false, description: "End date"
  argument :is_dashboard, Boolean, required: false, description: "Arg used only in admin dashboard"
  argument :payment_gateway_id, Integer, required: false, description: "Payment gateway id"
  argument :q, GraphQL::Types::JSON, required: false, description: "argument used for ransack filter"
  argument :start_date, GraphQL::Types::ISO8601Date, required: false, description: "Start date"
  argument :type, Integer, required: true, description: "Argument used to differentiate between transactions and invoices"

  def fetch_data
    @school = context[:school]
    @author = context[:author]
    @current_user = context[:current_user]
    author_course_ids = policy_scope(Course, policy_scope_class: RestrictedCoursePolicy::Scope).select(:id).courses_of_school(@school).pluck(:id) unless @current_user.role_id == User::OWNER_ROLE
    filter_condition = { school_id: context[:school].id }
    filter_condition[:course_id] = author_course_ids if author_course_ids.present?
    ransack_filter = parse_filter_query(custom_filter_fields: CUSTOM_FILTER_FIELDS)
    join_query = @options[:type] == INVOICES ? "#{DEFAULT_JOIN_QUERY} inner join learner_invoices on learner_invoices.order_id = orders.id and learner_invoices.school_id = orders.school_id" : DEFAULT_JOIN_QUERY
    select_fields = @options[:type] == INVOICES ? DEFAULT_SELECT_FIELDS + %w[learner_invoices.invoice_id learner_invoices.invoice_file_name learner_invoices.amount learner_invoices.tax_amount learner_invoices.is_sgst_cgst_order] : DEFAULT_SELECT_FIELDS
    filter_condition[:transaction_status] = Order::TRANSACTION_SUCCESS if @options[:type] == INVOICES
    filter_condition[:payment_gateway_id] = @options[:payment_gateway_id] if @options[:payment_gateway_id].present?
    if @options[:is_dashboard]
      end_date = Time.zone.today + 1.day
      @options[:end_date] = end_date
      @options[:start_date] = end_date.beginning_of_month
    end
    base_query = Order.select(select_fields + ALIAS_FIELDS)
                     .joins(join_query)
                     .where(filter_condition)
                     .where(build_custom_filter(config: @custom_filter_config))

    unless ransack_filter&.dig("type_of_payment_eq").present?
      base_query = base_query.where.not(type_of_payment: :parent_payment)
    end

    base_query = base_query.apply_date_range(@options[:start_date], @options[:end_date]) if date_range.values.all?
    @scope = base_query.order("orders.id" => :desc).ransack(ransack_filter)
    sort_results
  end

  def authorized?(obj)
    super(obj, "filters:search")
  end

end
