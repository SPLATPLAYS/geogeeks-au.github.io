require 'net/http'
require 'json'

module Jekyll
  class CommonsGalleryGenerator < Generator
    safe true
    priority :low

    def generate(site)
      site.pages.each do |page|
        category = page.data['commons_category']
        next if category.nil? || category.to_s.strip.empty?

        gallery_html = fetch_gallery(category.to_s)
        page.data['commons_gallery_html'] = gallery_html unless gallery_html.nil?
      end
    end

    private

    def fetch_gallery(category)
      category_key = category.strip.gsub(' ', '_')
      pages = fetch_category_members(category_key)
      return nil if pages.nil? || pages.empty?

      labels = fetch_entity_labels(pages)
      return nil if labels.nil?

      photos = build_photos(pages, labels, category_key)
      return nil if photos.empty?

      photos.sort_by! { |p| p[:time] }
      photos.map { |p| render_photo(p) }.join("\n")
    rescue => e
      Jekyll.logger.warn "CommonsGallery:", "Failed to fetch gallery for #{category}: #{e.message}"
      nil
    end

    @@last_api_call = Time.at(0)

    def api_call(params)
      elapsed = Time.now - @@last_api_call
      sleep(0.3 - elapsed) if elapsed < 0.3
      uri = URI('https://commons.wikimedia.org/w/api.php')
      uri.query = URI.encode_www_form(params.merge('format' => 'json', 'formatversion' => '2'))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 15
      http.open_timeout = 10
      response = http.get(uri.request_uri, 'User-Agent' => 'GeogeeksJekyll/1.0 (https://geogeeks.org)')
      @@last_api_call = Time.now
      JSON.parse(response.body)
    rescue => e
      Jekyll.logger.warn "CommonsGallery:", "API call failed: #{e.message}"
      nil
    end

    def fetch_category_members(category)
      result = api_call(
        'action' => 'query',
        'prop' => 'imageinfo',
        'generator' => 'categorymembers',
        'iiprop' => 'url|metadata',
        'iiurlwidth' => '255',
        'gcmtitle' => "Category:#{category}",
        'gcmlimit' => '50',
        'gcmtype' => 'file'
      )
      return nil if result.nil? || result['query'].nil?
      result['query']['pages']
    end

    def fetch_entity_labels(pages)
      media_ids = pages.map { |p| "M#{p['pageid']}" }.join('|')
      result = api_call(
        'action' => 'wbgetentities',
        'ids' => media_ids
      )
      return nil if result.nil? || result['entities'].nil?
      result['entities']
    end

    def build_photos(pages, entities, category)
      photos = []
      pages.each do |page|
        next if page['imageinfo'].nil? || page['imageinfo'].empty?

        info = page['imageinfo'][0]
        next if info['thumburl'].nil?

        time = ''
        (info['metadata'] || []).each do |meta|
          if meta['name'] == 'DateTimeOriginal'
            time = meta['value'][11, 5] || ''
            break
          end
        end

        caption = begin
          entities.dig("M#{page['pageid']}", 'labels', 'en', 'value') || '[No caption; please add one!]'
        rescue
          '[No caption; please add one!]'
        end

        photos << {
          page_title: page['title'],
          url: "https://commons.wikimedia.org/wiki/Category:#{category}#/media/#{page['title']}",
          thumburl: info['thumburl'],
          thumbheight: info['thumbheight'].to_i,
          thumbwidth: info['thumbwidth'].to_i,
          time: time,
          caption: caption
        }
      end
      photos
    end

    def render_photo(p)
      colspan = p[:thumbheight] > p[:thumbwidth] ? '2' : '3'
      %(<a class="figure col-md-#{colspan} gallery-item gallery-item-cached" href="#{h(p[:url])}">
        <figure>
          <img src="#{h(p[:thumburl])}" class="figure-img img-fluid rounded" loading="lazy">
          <figcaption><strong>#{p[:time]}: </strong>#{h(p[:caption])}</figcaption>
        </figure>
      </a>).gsub(/\n\s*/, '')
    end

    def h(text)
      text.to_s
        .gsub('&', '&amp;')
        .gsub('<', '&lt;')
        .gsub('>', '&gt;')
        .gsub('"', '&quot;')
    end
  end
end
