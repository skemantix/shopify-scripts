# Define a list of price tiers.
PRICE_TIERS = [
  # Pricing tiers for Batteries
  {
    product_types: ['Discount Batteries'],
    group_by: :product, # :product or :variant
    tiers: [
      {
        quantity: 5,
        discount_percentage: 60,
        discount_message_percentage: '60% off for 5+',
        discount_message_per_unit: ' each for 5+'
      },
      {
        quantity: 10,
        discount_percentage: 65,
        discount_message_percentage: '65% off for 10+',
        discount_message_per_unit: ' each for 10+'
      },
      {
        quantity: 20,
        discount_percentage: 67.5,
        discount_message_percentage: '67.5% off for 20+',
        discount_message_per_unit: ' each for 20+'
      },
      {
        quantity: 50,
        discount_percentage: 71,
        discount_message_percentage: '71% off for 50+',
        discount_message_per_unit: ' each for 50+'
      },
      {
        quantity: 100,
        discount_percentage: 75.5,
        discount_message_percentage: '75.5% off for 100+',
        discount_message_per_unit: ' each for 100+'
      }
    ]
  }
]

# You shouldn't need to edit anything below this line, unless you're a developer
# and know what you're doing :).

##
# Tiered pricing campaign.
class TieredPricingCampaign

  def initialize(partitioner, tiers)
    @partitioner = partitioner
    @tiers = tiers.sort_by { |tier| tier[:quantity] }
  end

  def run(cart)
    @partitioner.partition(cart).each do |k, items|
      total_quantity = items.map(&:quantity).reduce(0, :+)
      applicable_tier = find_tier_for_quantity(total_quantity)
      unless applicable_tier.nil?
        apply_tier_discount(items, applicable_tier)
      end
    end
  end

  private

    def find_tier_for_quantity(quantity)
      @tiers.select { |tier| tier[:quantity] <= quantity }.last
    end

    def apply_tier_discount(items, tier)
      discount = get_tier_discount(tier)
      items.each do |item|
        discount.apply(item)
      end
    end

    def get_tier_discount(tier)
      PercentageDiscount.new(tier[:discount_percentage], tier[:discount_message_per_unit], 'per_unit')
    end

end

##
# Select line items by product type.
class ProductTypeSelector

  def initialize(product_types)
    @product_types = Array(product_types).map(&:upcase)
  end

  def match?(line_item)
    @product_types.include?(line_item.variant.product.product_type.upcase)
  end

  def group_key
    @product_types.join(',')
  end

end

##
# Apply a percentage discount to a line item.
class PercentageDiscount

  def initialize(percent, message = '', message_type = 'percentage') # 'per_unit'
    @percent_raw = percent / 100.0
    @percent = Decimal.new(percent) / 100.0
    @message = message
    @message_type = message_type
  end

  def apply(item)
  
    line_discount = item.original_line_price * @percent
    
    # Reduce significant digits to 2 for per_unit (cents); take the floor
    if @message_type == 'per_unit'
      raw_price_cents = Float(item.variant.price.cents.to_s)
      raw_line_item_discount = (raw_price_cents * @percent_raw).floor
      line_item_discount = Money.new(cents:raw_line_item_discount)
      line_discount = item.quantity * line_item_discount
    end
    
    new_line_price = item.original_line_price - line_discount
    
    if @message_type == 'per_unit'
      per_item_price = new_line_price * (1/line_item.quantity)
      raw_per_item = Float(per_item_price.cents.to_s) / 100
      lineDivmod = raw_per_item.divmod 1
      lineDivmod[1] = lineDivmod[1].round(2).to_s.split('.').last.ljust(2, '0')
      per_item_formatted = lineDivmod.join(".")
      @message = "Bulk discount: $#{per_item_formatted}#{@message}")
    end
    
    if new_line_price < item.line_price
      item.change_line_price(new_line_price, message: @message)
    end
  end

end

##
# A pricing tier partition.
class TierPartitioner

  def initialize(selector, group_by)
    @selector = selector
    @group_by = group_by
  end

  def partition(cart)
    # Filter items
    items = cart.line_items.select { |item| @selector.match?(item) }

    # Group filtered items using the appropriate key.
    items.group_by { |item| group_key(item) }
  end

  private

    def group_key(line_item)
      case @group_by
        when :product
          line_item.variant.product.id
        when :variant
          line_item.variant.id
        else
          @selector.group_key
      end
    end

end

##
# Instantiate and run Price Tiers.
PRICE_TIERS.each do |pt|
  TieredPricingCampaign.new(
    TierPartitioner.new(
      ProductTypeSelector.new(pt[:product_types]),
      pt[:group_by]
    ),
    pt[:tiers]
  ).run(Input.cart)
end

##
# Export changes.
Output.cart = Input.cart
