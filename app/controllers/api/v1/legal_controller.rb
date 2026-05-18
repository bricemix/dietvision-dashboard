module Api
  module V1
    # Public endpoint — no authentication required.
    # GET /api/v1/legal/rgpd?region=eu   → document RGPD pour la région
    # GET /api/v1/legal/cgu?region=eu    → document CGU pour la région
    # Fallback : si aucun document pour la région → retourne le document "global"
    class LegalController < BaseController
      skip_authentication :rgpd, :cgu, :regions

      # GET /api/v1/legal/rgpd
      def rgpd
        region = sanitize_region(params[:region])
        doc    = LegalDocument.current(type: "rgpd", region: region)
        render_doc(doc, region)
      end

      # GET /api/v1/legal/cgu
      def cgu
        region = sanitize_region(params[:region])
        doc    = LegalDocument.current(type: "cgu", region: region)
        render_doc(doc, region)
      end

      # GET /api/v1/legal/regions — liste toutes les régions disponibles
      def regions
        available = LegalDocument::REGIONS.map do |key, info|
          has_rgpd = LegalDocument.current(type: "rgpd", region: key).present?
          has_cgu  = LegalDocument.current(type: "cgu",  region: key).present?
          {
            region:      key,
            label:       info[:label],
            law:         info[:law],
            has_rgpd:    has_rgpd,
            has_cgu:     has_cgu
          }
        end
        render json: available
      end

      private

      def sanitize_region(r)
        r = r.to_s.downcase.strip
        LegalDocument::REGIONS.key?(r) ? r : "eu"
      end

      def render_doc(doc, region)
        if doc&.file&.attached?
          render json: {
            url:        rails_blob_url(doc.file, disposition: "inline", host: request.base_url),
            version:    doc.version,
            region:     doc.region,
            region_label: doc.region_label,
            law:        doc.law_label,
            updated_at: doc.updated_at.iso8601,
            filename:   doc.filename,
            fallback:   doc.region != region
          }
        else
          render json: {
            url: nil, version: nil, region: region,
            region_label: LegalDocument::REGIONS.dig(region, :label),
            law: LegalDocument::REGIONS.dig(region, :law),
            updated_at: nil, filename: nil, fallback: false
          }
        end
      end
    end
  end
end
