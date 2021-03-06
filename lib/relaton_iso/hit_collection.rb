# frozen_string_literal: true

require "relaton_iso/hit"

module RelatonIso
  # Page of hit collection.
  class HitCollection < RelatonBib::HitCollection
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength

    # @param text [String] reference to search
    def initialize(text)
      super
      %r{\s(?<num>\d+)(-(?<part>[\d-]+))?} =~ text
      http = Net::HTTP.new "www.iso.org", 443
      http.use_ssl = true
      search = ["status=ENT_ACTIVE,ENT_PROGRESS,ENT_INACTIVE,ENT_DELETED"]
      search << "docNumber=#{num}"
      search << "docPartNo=#{part}" if part
      q = search.join "&"
      resp = http.get("/cms/render/live/en/sites/isoorg.advancedSearch.do?#{q}",
                      "Accept" => "application/json, text/plain, */*")
      return if resp.body.empty?

      json = JSON.parse resp.body
      @array = json["standards"].map { |h| Hit.new h, self }.sort! do |a, b|
        if a.sort_weight == b.sort_weight
          (parse_date(b.hit) - parse_date(a.hit)).to_i
        else
          a.sort_weight - b.sort_weight
        end
      end
    end

    # @param lang [String, NilClass]
    # @return [RelatonIsoBib::IsoBibliographicItem]
    def to_all_parts(lang = nil) # rubocop:disable Metrics/CyclomaticComplexity
      parts = @array.reject { |h| h.hit["docPart"]&.empty? }
      hit = parts.min_by { |h| h.hit["docPart"].to_i }
      return @array.first.fetch lang unless hit

      bibitem = hit.fetch lang
      all_parts_item = bibitem.to_all_parts
      parts.reject { |h| h.hit["docRef"] == hit.hit["docRef"] }.each do |hi|
        isobib = RelatonIsoBib::IsoBibliographicItem.new(
          formattedref: RelatonBib::FormattedRef.new(content: hi.hit["docRef"])
        )
        all_parts_item.relation << RelatonBib::DocumentRelation.new(
          type: "instance", bibitem: isobib
        )
      end
      all_parts_item
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    # @param hit [Hash]
    # @return [Date]
    def parse_date(hit)
      if hit["publicationDate"]
        Date.strptime(hit["publicationDate"], "%Y-%m")
      elsif %r{:(?<year>\d{4})} =~ hit["docRef"]
        Date.strptime(year, "%Y")
      elsif hit["newProjectDate"]
        Date.parse hit["newProjectDate"]
      else
        Date.new 0
      end
    end
  end
end
