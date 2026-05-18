class LegalDocument < ApplicationRecord
  TYPES   = %w[rgpd cgu].freeze
  REGIONS = {
    "eu"     => { label: "🇪🇺 Union Européenne",  law: "RGPD — UE 2016/679" },
    "us"     => { label: "🇺🇸 États-Unis",         law: "CCPA / US Privacy Law" },
    "uk"     => { label: "🇬🇧 Royaume-Uni",        law: "UK GDPR" },
    "ca"     => { label: "🇨🇦 Canada",             law: "PIPEDA / Law 25 QC" },
    "br"     => { label: "🇧🇷 Brésil",             law: "LGPD" },
    "global" => { label: "🌍 Mondial (défaut)",    law: "Politique générale" }
  }.freeze

  belongs_to :admin_user, optional: true
  has_one_attached :file

  validates :document_type, inclusion: { in: TYPES }
  validates :region,        inclusion: { in: REGIONS.keys }
  validates :file, presence: { message: "Veuillez sélectionner un fichier" }

  scope :of_type,  ->(t) { where(document_type: t) }
  scope :active,   -> { where(active: true) }
  scope :for_region, ->(r) { where(region: r) }

  # Retourne le document actif pour un type + région donnés
  # Fallback : global si aucun actif pour la région
  def self.current(type: "rgpd", region: "eu")
    doc = of_type(type).active.for_region(region).order(created_at: :desc).first
    doc ||= of_type(type).active.for_region("global").order(created_at: :desc).first
    doc
  end

  def activate!
    LegalDocument.where(document_type: document_type, region: region).update_all(active: false)
    update!(active: true)
  end

  def type_label    = document_type.upcase
  def region_label  = REGIONS.dig(region, :label) || region.upcase
  def law_label     = REGIONS.dig(region, :law) || ""

  def filename
    file.attached? ? file.blob.filename.to_s : "—"
  end

  def filesize_human
    return "—" unless file.attached?
    bytes = file.blob.byte_size
    if bytes < 1024         then "#{bytes} o"
    elsif bytes < 1_048_576 then "#{"%.1f" % (bytes / 1024.0)} Ko"
    else                         "#{"%.1f" % (bytes / 1_048_576.0)} Mo"
    end
  end
end
