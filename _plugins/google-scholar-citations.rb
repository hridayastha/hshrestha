require "active_support/all"
require 'nokogiri'
require 'open-uri'

module Helpers
  extend ActiveSupport::NumberHelper
end

module Jekyll
  class GoogleScholarCitationsTag < Liquid::Tag
    Citations = {}

    def initialize(tag_name, params, tokens)
      super
      splitted = params.split(" ").map(&:strip)
      @scholar_id = splitted[0]
      @article_id = splitted[1]
    end

    def render(context)
      article_id = context[@article_id.strip] || @article_id.strip
      scholar_id = context[@scholar_id.strip] || @scholar_id.strip
      article_url = "https://scholar.google.com/citations?view_op=view_citation&hl=en&user=#{scholar_id}&citation_for_view=#{scholar_id}:#{article_id}"

      begin
        # If the citation count has already been fetched, return it
        if GoogleScholarCitationsTag::Citations[article_id]
          return GoogleScholarCitationsTag::Citations[article_id]
        end

        # Sleep to mitigate rate limiting
        sleep(rand(5.0..10.0))

        headers = {
          "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
          "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
          "Accept-Language" => "en-US,en;q=0.9",
          "Cache-Control" => "max-age=0"
        }

        doc = Nokogiri::HTML(URI.open(article_url, headers))

        citation_count = 0

        # Look for the "Cited by" link inside the fields column
        # Google Scholar typically uses links containing "cites=" for the count
        cited_by_link = doc.xpath("//a[contains(@href, 'cites=')]").first

        if cited_by_link
          cited_by_text = cited_by_link.text # e.g., "Cited by 142"
          matches = cited_by_text.match(/Cited by (\d+[,\d]*)/)
          if matches
            citation_count = matches[1].gsub(",", "").to_i
          end
        else
          # Fallback: Check if the text actually just displays an integer in the right field element
          # If Google returns a CAPTCHA page, this code block won't find anything either
          div_field = doc.css('.gsc_oci_value a').first
          if div_field && div_field.text =~ /\d+/
            citation_count = div_field.text.to_i
          end
        end

        # Humanize the number (e.g., 1.2K)
        formatted_count = Helpers.number_to_human(citation_count, :format => '%n%u', :precision => 2, :units => { :thousand => 'K', :million => 'M', :billion => 'B' })
        # Clean up trailing decimals if exact (e.g., "1.0K" -> "1K")
        formatted_count = formatted_count.sub(/\.0(?=[KMB])/, '')

      rescue OpenURI::HTTPError => e
        formatted_count = "N/A"
        puts "HTTP Error fetching citation count for #{article_id}: #{e.message} - Google might be blocking you."
      rescue Exception => e
        formatted_count = "N/A"
        puts "Error fetching citation count for #{article_id}: #{e.class} - #{e.message}"
      end

      GoogleScholarCitationsTag::Citations[article_id] = formatted_count
      return "#{formatted_count}"
    end
  end
end

Liquid::Template.register_tag('google_scholar_citations', Jekyll::GoogleScholarCitationsTag)
