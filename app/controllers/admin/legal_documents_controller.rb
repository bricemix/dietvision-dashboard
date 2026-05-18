module Admin
  class LegalDocumentsController < BaseController

    def index
      # Groupe par type puis région pour l'affichage
      @docs_by_type = {}
      %w[rgpd cgu].each do |type|
        @docs_by_type[type] = LegalDocument
          .of_type(type)
          .with_attached_file
          .order(region: :asc, created_at: :desc)
          .group_by(&:region)
      end

      # Documents actifs par région (pour le tableau de bord)
      @active_by_region = {}
      LegalDocument::REGIONS.each_key do |region|
        @active_by_region[region] = {
          rgpd: LegalDocument.current(type: "rgpd", region: region),
          cgu:  LegalDocument.current(type: "cgu",  region: region)
        }
      end
    end

    def create
      @doc = LegalDocument.new(legal_document_params)
      @doc.admin_user_id = current_admin.id

      if @doc.save
        @doc.activate! if params[:activate] == "1"
        AdminLog.log(
          admin: current_admin,
          action: "upload_legal_document",
          resource: @doc,
          details: { type: @doc.document_type, region: @doc.region, version: @doc.version },
          ip: request.remote_ip
        )
        msg = "Document #{@doc.type_label} #{@doc.region_label} v#{@doc.version} uploadé"
        msg += " et activé" if params[:activate] == "1"
        redirect_to admin_legal_documents_path, notice: "#{msg}."
      else
        @docs_by_type = {}
        %w[rgpd cgu].each do |type|
          @docs_by_type[type] = LegalDocument.of_type(type).with_attached_file
                                   .order(region: :asc, created_at: :desc).group_by(&:region)
        end
        @active_by_region = {}
        LegalDocument::REGIONS.each_key do |region|
          @active_by_region[region] = {
            rgpd: LegalDocument.current(type: "rgpd", region: region),
            cgu:  LegalDocument.current(type: "cgu",  region: region)
          }
        end
        flash.now[:alert] = @doc.errors.full_messages.join(" · ")
        render :index, status: :unprocessable_entity
      end
    end

    def activate
      @doc = LegalDocument.find(params[:id])
      @doc.activate!
      AdminLog.log(
        admin: current_admin,
        action: "activate_legal_document",
        resource: @doc,
        details: { type: @doc.document_type, region: @doc.region },
        ip: request.remote_ip
      )
      redirect_to admin_legal_documents_path,
                  notice: "#{@doc.type_label} #{@doc.region_label} v#{@doc.version} activé."
    end

    def destroy
      @doc = LegalDocument.find(params[:id])
      if @doc.active?
        return redirect_to admin_legal_documents_path,
                           alert: "Impossible de supprimer un document actif. Activez d'abord une autre version."
      end
      @doc.file.purge if @doc.file.attached?
      @doc.destroy
      AdminLog.log(admin: current_admin, action: "delete_legal_document",
                   details: { type: @doc.document_type, region: @doc.region, version: @doc.version },
                   ip: request.remote_ip)
      redirect_to admin_legal_documents_path, notice: "Document supprimé."
    end

    private

    def legal_document_params
      params.require(:legal_document).permit(:document_type, :region, :version, :notes, :file)
    end
  end
end
