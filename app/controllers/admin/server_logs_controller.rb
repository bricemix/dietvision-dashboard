module Admin
  class ServerLogsController < BaseController
    LOG_FILE    = Rails.root.join("log", "puma.log").to_s
    MAX_LINES   = 5_000   # lignes lues depuis la fin du fichier
    PER_PAGE    = 100     # lignes affichées par page

    def index
      lines = read_log_lines

      # ── Filtres ────────────────────────────────────────────────────────────
      lines = filter_by_level(lines,   params[:level])
      lines = filter_by_source(lines,  params[:source])
      lines = filter_by_keyword(lines, params[:keyword])
      lines = filter_by_date(lines,    params[:date_from], params[:date_to])

      # ── Stats ──────────────────────────────────────────────────────────────
      @total_lines = lines.size
      @error_count = lines.count { |l| l[:level] == "ERROR" }
      @warn_count  = lines.count { |l| l[:level] == "WARN"  }

      # ── Pagination manuelle ────────────────────────────────────────────────
      @current_page = [ params[:page].to_i, 1 ].max
      @total_pages  = [ (@total_lines.to_f / PER_PAGE).ceil, 1 ].max
      @current_page = @total_pages if @current_page > @total_pages

      offset = (@current_page - 1) * PER_PAGE
      @lines = lines[offset, PER_PAGE] || []

      # ── Nom du fichier ──────────────────────────────────────────────────────
      @log_file_name = File.basename(LOG_FILE)
      @log_file_size = File.exist?(LOG_FILE) ? human_file_size(File.size(LOG_FILE)) : "–"
    end

    # GET /admin/server_logs/download
    def download
      if File.exist?(LOG_FILE)
        send_file LOG_FILE,
          filename: "dietvision-#{Date.today.iso8601}.log",
          type: "text/plain",
          disposition: "attachment"
      else
        redirect_to admin_server_logs_path, alert: "Fichier log introuvable"
      end
    end

    # DELETE /admin/server_logs/clear
    def clear
      if File.exist?(LOG_FILE)
        File.write(LOG_FILE, "")
        redirect_to admin_server_logs_path, notice: "Logs effacés"
      else
        redirect_to admin_server_logs_path, alert: "Fichier log introuvable"
      end
    end

    private

    # ── Lecture du fichier ──────────────────────────────────────────────────

    def read_log_lines
      return [] unless File.exist?(LOG_FILE)

      raw_lines = tail_file(LOG_FILE, MAX_LINES)
      parsed = []

      raw_lines.each_with_index do |raw, idx|
        parsed << parse_line(raw.strip, idx)
      end

      # Ordre chronologique inversé (plus récent en premier)
      parsed.reverse
    end

    # Lit les N dernières lignes en remontant depuis la fin du fichier.
    # BUG-11 FIXÉ : ancienne version faisait File.binread(path) → charge tout le fichier en RAM.
    # Nouvelle version lit des chunks depuis la fin (O(chunk_size) en RAM, pas O(file_size)).
    CHUNK_SIZE = 512.kilobytes

    def tail_file(path, n)
      File.open(path, "rb") do |f|
        size     = f.size
        return [] if size == 0

        buffer   = +""
        offset   = size
        lines    = []

        while lines.size < n && offset > 0
          read_size = [ CHUNK_SIZE, offset ].min
          offset   -= read_size
          f.seek(offset)
          chunk = f.read(read_size)
          # Forcer UTF-8 pour éviter les erreurs sur requêtes HTTP malformées
          chunk = chunk.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "?")
          buffer = chunk + buffer
          lines  = buffer.lines
          # Supprimer la première ligne (potentiellement tronquée) si on n'est pas au début
          lines.shift if offset > 0 && lines.size > 1
        end

        lines.last(n)
      end
    rescue => e
      Rails.logger.error("ServerLogsController#tail_file error: #{e.message}")
      []
    end

    # ── Parser une ligne ────────────────────────────────────────────────────

    LOG_PATTERN = /
      \A
      \[(?<uuid>[a-f0-9\-]{36})\]\s+   # [uuid]
      (?<message>.+)                    # reste
      \z
    /x

    TIMESTAMP_PATTERN = /at\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/

    def parse_line(raw, idx)
      # S'assurer que la ligne est proprement encodée avant tout traitement
      safe_raw = safe_utf8(raw)
      level    = detect_level(safe_raw)
      source   = detect_source(safe_raw)
      ts       = extract_timestamp(safe_raw)
      uuid     = nil
      message  = safe_raw

      if (m = safe_raw.match(LOG_PATTERN))
        uuid    = m[:uuid]
        message = m[:message]
      end

      {
        id:        idx,
        uuid:      uuid,
        timestamp: ts,
        level:     level,
        source:    source,
        message:   message.strip,
        raw:       safe_raw
      }
    rescue => e
      # Ligne totalement illisible → on l'affiche comme DEBUG brut
      { id: idx, uuid: nil, timestamp: nil, level: "DEBUG",
        source: "Système", message: "(ligne illisible)", raw: raw.to_s }
    end

    def detect_level(line)
      return "ERROR" if line.match?(/error|exception|traceback|errno|failed|fatal/i)
      return "WARN"  if line.match?(/warn|deprecated|slow|timeout/i)
      return "INFO"  if line.match?(/Started|Completed|Processing|Puma|Ruby/i)
      "DEBUG"
    rescue Encoding::CompatibilityError
      "DEBUG"
    end

    def detect_source(line)
      return "API"   if line.match?(%r{/api/v1})
      return "Admin" if line.match?(%r{/admin})
      return "Puma"  if line.match?(/Puma|puma/i)
      return "Rails" if line.match?(/Started|Completed|Processing/i)
      "Système"
    rescue Encoding::CompatibilityError
      "Système"
    end

    def extract_timestamp(line)
      if (m = line.match(TIMESTAMP_PATTERN))
        Time.parse(m[1]) rescue nil
      end
    end

    # ── Filtres ─────────────────────────────────────────────────────────────

    def filter_by_level(lines, level)
      return lines if level.blank? || level == "all"
      lines.select { |l| l[:level] == level.upcase }
    end

    def filter_by_source(lines, source)
      return lines if source.blank? || source == "all"
      lines.select { |l| l[:source] == source }
    end

    def filter_by_keyword(lines, keyword)
      return lines if keyword.blank?
      kw = keyword.downcase
      lines.select { |l| safe_utf8(l[:raw]).downcase.include?(kw) }
    end

    def filter_by_date(lines, from, to)
      return lines if from.blank? && to.blank?
      lines.select do |l|
        next true unless l[:timestamp]
        ts = l[:timestamp]
        ok = true
        ok &&= ts >= Time.zone.parse(from).beginning_of_day rescue true if from.present?
        ok &&= ts <= Time.zone.parse(to).end_of_day          rescue true if to.present?
        ok
      end
    end

    # Convertit une chaîne en UTF-8 valide en remplaçant les octets invalides
    def safe_utf8(str)
      str.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
    end

    def human_file_size(bytes)
      if bytes < 1024
        "#{bytes} B"
      elsif bytes < 1024 * 1024
        "#{"%.1f" % (bytes / 1024.0)} KB"
      else
        "#{"%.1f" % (bytes / (1024.0 * 1024))} MB"
      end
    end
  end
end
