module ONIX
  module ONIX21
    class ShortToRef
      def self.names
        @shortnames||=YAML.load(File.open(File.dirname(__FILE__) + "/../../data/onix21/shortnames.yml"))
      end
    end

    class RefToShort
      def self.names
        @refnames||=ShortToRef.names.invert
      end
    end

    class SubsetDSL < ONIX::SubsetDSL
      def self.short_to_ref(name)
        ONIX::ONIX21::ShortToRef.names[name]
      end
      def self.ref_to_short(name)
        ONIX::ONIX21::RefToShort.names[name]
      end

      def self.get_class(name)
        if ONIX::ONIX21.const_defined?(name)
          ONIX::ONIX21.const_get(name)
        else
          ONIX.const_get(name)
        end
      end
    end

    class Title < SubsetDSL
      element "TitleType", :subset
      element "TitleText", :text
      element "TitlePrefix", :text
      element "TitleWithoutPrefix", :text
      element "AbbreviatedLength", :integer
      element "Subtitle", :text

      def type
        @title_type
      end

      def title
        @title_text
      end
    end

    class OtherText < SubsetDSL
      element "TextTypeCode", :text
      element "TextFormat", :text
      element "Text", :text

      def type_code
        @text_type_code
      end
    end

    class Territory
      attr_accessor :countries

      def initialize(countries)
        @countries=countries
      end

      def +v
        Territory.new((@countries + v.countries).uniq)
      end

      def -v
        Territory.new((@countries - v.countries).uniq)
      end
    end

    class Price < SubsetDSL
      element "PriceTypeCode", :subset, :klass => "PriceType"
      element "PriceAmount", :float, {:lambda => lambda { |v| (v*100).round }}
      element "DiscountCoded", :subset
      element "CurrencyCode", :text
      elements "CountryCode", :text

      def amount
        @price_amount
      end

      def currency
        @currency_code
      end

      def including_tax?
        if @price_type_code.human =~/IncludingTax/
          true
        else
          false
        end
      end

      def from_date
        nil
      end

      def until_date
        nil
      end

      def territory
        Territory.new(@country_codes)
      end
    end

    class SupplyDetail < SubsetDSL
      element "SupplierName", :text
      element "TelephoneNumber", :text
      element "SupplierRole", :text

      element "AvailabilityCode", :text
      element "ProductAvailability", :text
      element "OnSaleDate", :text, {:lambda => lambda { |v| Date.strptime(v, "%Y%m%d") }}
      elements "Price", :subset

      def availability_date
        @on_sale_date
      end

      def available?
        @product_availability=="20"
      end
    end

    class SalesRights < SubsetDSL
      element "SalesRightsType", :text
      element "RightsCountry", :text

      def not_for_sale?
        ["03","04","05","06"].include?(@sales_rights_type)
      end

      def territory
        Territory.new(@rights_country.split(" "))
      end
    end

    class NotForSale < SubsetDSL
      element "RightsCountry", :text

      def territory
        Territory.new(@rights_country.split(" "))
      end
    end

    class RelatedProduct < SubsetDSL
      include EanMethods
      include ProprietaryIdMethods

      element "RelationCode", :text
      elements "ProductIdentifier", :subset

      def identifiers
        @product_identifiers
      end

      def code
        @relation_code
      end
    end

    class Product < SubsetDSL
      include EanMethods
      include ProprietaryIdMethods

      element "RecordReference", :text
      elements "ProductIdentifier", :subset
      element "NotificationType", :subset
      element "RecordSourceName", :text
      elements "Title", :subset
      elements "ProductSupply", :subset

      elements "Contributor", :subset
      element "ContributorStatement", :text

      elements "Extent", :subset
      elements "Language", :subset

      elements "Publisher", :subset
      elements "Imprint", :subset

      element "ProductForm", :text

      elements "OtherText", :subset

      elements "SalesRights", :subset, {:pluralize => false}
      elements "NotForSale", :subset

      element "BASICMainSubject", :text
      elements "Subject", :subset

      element "PublishingStatus", :text
      element "PublicationDate", :text, {:lambda => lambda { |v| Date.strptime(v, "%Y%m%d") }}

      elements "RelatedProduct", :subset

      elements "SupplyDetail", :subset

      element "EpubType", :text
      element "EpubTypeDescription", :text
      element "EpubFormat", :text
      element "EpubTypeNote", :text

      element "NoEdition", :ignore
      element "NoSeries", :ignore

      # shortcuts
      def identifiers
        @product_identifiers
      end

      # default LanguageCode from ONIXMessage
      attr_accessor :default_language_of_text
      # default code from ONIXMessage
      attr_accessor :default_currency_code

      def title
        product_title.title
      end

      # :category: High level
      # product subtitle string
      def subtitle
        product_title.subtitle
      end

      def product_title
        @titles.select { |td| td.type.human=~/DistinctiveTitle/ }.first
      end

      def bisac_categories_codes
        cats=[]
        if @basic_main_subject
          cats << @basic_main_subject
        end
        cats+=@subjects.select { |s| s.scheme_identifier.human=="BisacSubjectHeading" }.map{|s| s.code}
        cats
      end

      # TODO ?
      def clil_categories_codes
        []
      end

      # TODO
      def keywords
        []
      end

      # doesn't apply
      def onix_outlets_values
        []
      end

      # product LanguageCode of text
      def language_of_text
        lang=nil
        l=@languages.select { |l| l.role.human=="LanguageOfText" }.first
        if l
          lang=l.code
        end
        lang || @default_language_of_text
      end

      def language_code_of_text
        if self.language_of_text
          self.language_of_text.code
        end
      end

      def language_name_of_text
        if self.language_of_text
          self.language_of_text.human
        end
      end

      def publisher_name
        if @publishers.first
          @publishers.first.name
        end
      end

      def imprint_name
        if @imprints.first
          @imprints.first.name
        end
      end

      # doesn't apply
      def sold_separately?
        true
      end

      def description
        desc_contents=@other_texts.select { |tc| tc.type_code=="03" } + @other_texts.select { |tc| tc.type_code=="01" } + @other_texts.select { |tc| tc.type_code=="13" }
        if desc_contents.length > 0
          desc_contents.first.text
        else
          nil
        end
      end

      def raw_description
        if self.description
          Helper.strip_html(self.description).gsub(/\s+/, " ").strip
        else
          nil
        end
      end

      def product_supplies
        [self]
      end

      def countries
        territory=Territory.new(CountryCode.list)
        @sales_rights.each do |sr|
          if sr.not_for_sale?
            territory=territory-sr.territory
          else
            territory=territory+sr.territory
          end
        end

        @not_for_sales.each do |sr|
          territory=territory-sr.territory
        end

        territory.countries
      end

      def availability_date
        nil
      end

      include ProductSuppliesExtractor

      def related
        @related_products
      end

      # doesn't apply
      def parts
        []
      end

      # doesn't apply
      def bundle?
        false
      end

      def digital?
        @product_form=="DG"
      end

      def available?
        @supply_details.select { |sd| sd.available? }.length > 0
      end

      def pages
        nil
      end

      def distributor_name
        nil
      end

      # TODO
      def publisher_collection_title
        nil
      end

      def file_format
        case @epub_type
          when "029"
            "Epub"
          when "002"
            "Pdf"
          else
            nil
        end
      end

      def file_description
        @epub_type_description
      end

      def raw_file_description
        file_description
      end

      # doesn't apply
      def filesize
        nil
      end

      # doesn't apply
      def protection_type
        nil
      end

      def frontcover_url
        nil
      end

      def epub_sample_url
        nil
      end

      def print_product
        @related_products.select { |rp| rp.code=="13" }.first
      end

      def method_missing(method)
        raise "WARN #{method} not found"
      end

    end
  end
end