-- =============================================================================
-- ORDER TRANSACTION DATA OPTIMIZATION
-- =============================================================================
-- This file documents the SQL query optimization for the order transactions
-- page. The original query fetched many columns and JOINs that are NOT used
-- by the frontend display.
--
-- Frontend displays ONLY these fields:
--   Name, Mobile, PAN, PAN Status, Date of Birth, Product Title,
--   Consent Status, Billing Address, Shipping Address, Place of Supply,
--   Tax Amount, Tax Applied %, Price, Home Currency Price, Purchased Date,
--   User ID, Invoice Number, Invoice, Email
--
-- Billing Address, Shipping Address, and Place of Supply are already
-- fetched via BatchLoader in the GraphQL type, so the LEFT JOIN to
-- addresses in the SQL query was redundant.
-- =============================================================================

-- =============================================================================
-- ORIGINAL QUERY (before optimization)
-- =============================================================================
-- SELECT DISTINCT
--   `orders`.`id`,
--   `users`.`name`,
--   `users`.`profile_photo_file_name`,     -- REMOVED: not displayed on frontend
--   `users`.`mobile`,
--   `users`.`pan`,
--   `users`.`pan_status`,
--   `users`.`dob`,
--   `users`.`email`,
--   `courses`.`title`,
--   `courses`.`course_type`,               -- REMOVED: not displayed on frontend
--   `orders`.`created_at`,
--   `orders`.`transaction_status`,          -- REMOVED: used in WHERE only, always = 2
--   `orders`.`transaction_id`,              -- REMOVED: not displayed on frontend
--   `orders`.`payment_type`,                -- REMOVED: not displayed on frontend
--   `orders`.`price`,
--   `orders`.`coupon_code`,                 -- REMOVED: not displayed on frontend
--   `orders`.`coupon_amount`,               -- REMOVED: not displayed on frontend
--   `orders`.`learner_invoice_id`,          -- REMOVED: not displayed on frontend
--   `orders`.`course_id`,                   -- REMOVED: not displayed on frontend
--   `orders`.`pg_order_id`,                 -- REMOVED: not displayed on frontend
--   `orders`.`pg_reference`,                -- REMOVED: not displayed on frontend
--   `orders`.`home_currency_amount`,
--   `orders`.`currency_code`,               -- REMOVED: not displayed on frontend
--   `orders`.`product_pricing_id`,          -- REMOVED: not displayed on frontend
--   `addresses`.`state`,                    -- REMOVED: fetched via BatchLoader
--   `addresses`.`country`,                  -- REMOVED: fetched via BatchLoader
--   `orders`.`user_consent_status`,
--   `orders`.`consent_page_id`,             -- REMOVED: not displayed on frontend
--   `orders`.`mrp`,                         -- REMOVED: not displayed on frontend
--   `orders`.`type_of_payment`,             -- REMOVED: used in WHERE only, not displayed
--   `learner_invoices`.`invoice_id`,
--   `learner_invoices`.`invoice_file_name`,
--   `learner_invoices`.`amount`,
--   `learner_invoices`.`tax_amount`,
--   `learner_invoices`.`is_sgst_cgst_order`,
--   users.id as user_id,
--   orders.school_id as school_id,
--   coupon_codes.code as tracking_code      -- REMOVED: not displayed on frontend
-- FROM `orders`
--   left join courses on orders.course_id = courses.id and orders.school_id = courses.school_id
--   left join users on orders.user_id = users.id
--   left join coupon_codes on coupon_codes.id = orders.tracking_id     -- REMOVED: entire JOIN
--     and coupon_codes.school_id = orders.school_id
--     and coupon_codes.coupon_type = 1
--   left join addresses on addresses.user_id = orders.user_id          -- REMOVED: entire JOIN
--     and addresses.school_id = orders.school_id
--     and addresses.address_type = 0
--   inner join learner_invoices on learner_invoices.order_id = orders.id
--     and learner_invoices.school_id = orders.school_id
-- WHERE `orders`.`school_id` = 182652
--   AND `orders`.`transaction_status` = 2
--   AND `orders`.`type_of_payment` != 2
-- ORDER BY `orders`.`id` DESC
-- LIMIT 10 OFFSET 0

-- =============================================================================
-- OPTIMIZED QUERY (after optimization)
-- =============================================================================
-- Removed 19 unnecessary SELECT columns
-- Removed 2 unnecessary LEFT JOINs (addresses, coupon_codes)
-- =============================================================================

SELECT DISTINCT
  `orders`.`id`,
  `users`.`name`,
  `users`.`mobile`,
  `users`.`pan`,
  `users`.`pan_status`,
  `users`.`dob`,
  `users`.`email`,
  `courses`.`title`,
  `orders`.`created_at`,
  `orders`.`price`,
  `orders`.`home_currency_amount`,
  `orders`.`user_consent_status`,
  `learner_invoices`.`invoice_id`,
  `learner_invoices`.`invoice_file_name`,
  `learner_invoices`.`amount`,
  `learner_invoices`.`tax_amount`,
  `learner_invoices`.`is_sgst_cgst_order`,
  users.id as user_id,
  orders.school_id as school_id
FROM `orders`
  LEFT JOIN courses ON orders.course_id = courses.id
    AND orders.school_id = courses.school_id
  LEFT JOIN users ON orders.user_id = users.id
  INNER JOIN learner_invoices ON learner_invoices.order_id = orders.id
    AND learner_invoices.school_id = orders.school_id
WHERE `orders`.`school_id` = 182652
  AND `orders`.`transaction_status` = 2
  AND `orders`.`type_of_payment` != 2
ORDER BY `orders`.`id` DESC
LIMIT 10 OFFSET 0;

-- =============================================================================
-- SUMMARY OF REMOVALS
-- =============================================================================
--
-- COLUMNS REMOVED FROM SELECT (19 columns):
-- +-----------------------------------------+------------------------------------------+
-- | Column                                  | Reason                                   |
-- +-----------------------------------------+------------------------------------------+
-- | users.profile_photo_file_name           | Not displayed on frontend                |
-- | courses.course_type                     | Not displayed on frontend                |
-- | orders.transaction_status               | Used in WHERE only, not displayed        |
-- | orders.transaction_id                   | Not displayed on frontend                |
-- | orders.payment_type                     | Not displayed on frontend                |
-- | orders.coupon_code                      | Not displayed on frontend                |
-- | orders.coupon_amount                    | Not displayed on frontend                |
-- | orders.learner_invoice_id               | Not displayed on frontend                |
-- | orders.course_id                        | Not displayed on frontend                |
-- | orders.pg_order_id                      | Not displayed on frontend                |
-- | orders.pg_reference                     | Not displayed on frontend                |
-- | orders.currency_code                    | Not displayed on frontend                |
-- | orders.product_pricing_id               | Not displayed on frontend                |
-- | addresses.state                         | Redundant: fetched via BatchLoader       |
-- | addresses.country                       | Redundant: fetched via BatchLoader       |
-- | orders.consent_page_id                  | Not displayed on frontend                |
-- | orders.mrp                              | Not displayed on frontend                |
-- | orders.type_of_payment                  | Used in WHERE only, not displayed        |
-- | coupon_codes.code (tracking_code)       | Not displayed on frontend                |
-- +-----------------------------------------+------------------------------------------+
--
-- JOINS REMOVED (2 JOINs):
-- +-----------------------------------------+------------------------------------------+
-- | JOIN                                    | Reason                                   |
-- +-----------------------------------------+------------------------------------------+
-- | LEFT JOIN addresses                     | Redundant: billing/shipping/place of     |
-- |                                         | supply fetched via BatchLoader in        |
-- |                                         | GraphQL type                             |
-- | LEFT JOIN coupon_codes                  | Only fetched tracking_code which is      |
-- |                                         | not displayed on frontend                |
-- +-----------------------------------------+------------------------------------------+
--
-- GRAPHQL FIELDS REMOVED (23 fields):
-- +-----------------------------------------+------------------------------------------+
-- | Field                                   | Reason                                   |
-- +-----------------------------------------+------------------------------------------+
-- | affiliate_payout                        | Not displayed on frontend                |
-- | consent_page_id                         | Not displayed on frontend                |
-- | country                                 | Not displayed on frontend                |
-- | coupon_amount                           | Not displayed on frontend                |
-- | coupon_code                             | Not displayed on frontend                |
-- | course_id                               | Not displayed on frontend                |
-- | course_type                             | Not displayed on frontend                |
-- | currency_code                           | Not displayed on frontend                |
-- | has_installments                        | Not displayed on frontend                |
-- | is_mob_verified                         | Not displayed on frontend                |
-- | mrp                                     | Not displayed on frontend                |
-- | payment_method                          | Not displayed on frontend                |
-- | payment_type                            | Not displayed on frontend                |
-- | pg_order_id                             | Not displayed on frontend                |
-- | pg_reference                            | Not displayed on frontend                |
-- | product_pricing                         | Not displayed on frontend                |
-- | product_pricing_id                      | Not displayed on frontend                |
-- | profile_photo_file_name                 | Not displayed on frontend                |
-- | remaining_amount                        | Not displayed on frontend                |
-- | tracking_code                           | Not displayed on frontend                |
-- | transaction_id                          | Not displayed on frontend                |
-- | transaction_status                      | Not displayed (always filtered to 2)     |
-- | type_of_payment                         | Not displayed on frontend                |
-- +-----------------------------------------+------------------------------------------+
--
-- GRAPHQL METHODS/RESOLVERS REMOVED:
--   - country (BatchLoader) - not displayed
--   - has_installments - not displayed
--   - remaining_amount (BatchLoader) - not displayed
--
-- ENUM_ATTRIBUTES REMOVED:
--   - payment_type -> Enums::Orders::PaymentTypeEnum
--   - transaction_status -> Enums::Orders::TransactionStatusEnum
--   - course_type -> Enums::Enrollments::ProductTypeEnum
--   - type_of_payment -> Enums::Orders::TypeOfPaymentEnum
--
-- IDENTIFIER_FIELDS REMOVED:
--   - username (not displayed on frontend, only email is needed)
--
-- COLUMNS KEPT (19 columns):
--   orders.id, users.name, users.mobile, users.pan, users.pan_status,
--   users.dob, users.email, courses.title, orders.created_at, orders.price,
--   orders.home_currency_amount, orders.user_consent_status,
--   learner_invoices.invoice_id, learner_invoices.invoice_file_name,
--   learner_invoices.amount, learner_invoices.tax_amount,
--   learner_invoices.is_sgst_cgst_order, users.id (as user_id),
--   orders.school_id (as school_id)
-- =============================================================================
