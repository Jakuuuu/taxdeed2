# frozen_string_literal: true

# ReportsController
# Gestiona descarga de PDFs y reintento de reportes fallidos.
# Rutas:
#   GET  /reports/:id/download  → descarga el PDF via Active Storage
#   POST /reports/:id/retry     → reencola el job si el reporte falló
class ReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_report

  # GET /reports/:id/download
  def download
    unless @report.pdf_file.attached?
      redirect_to research_purchased_reports_path,
                  alert: "El PDF aún no está disponible. Intenta de nuevo en unos momentos."
      return
    end

    redirect_to rails_blob_url(@report.pdf_file, disposition: "attachment"),
                allow_other_host: true
  end

  # POST /reports/:id/retry
  def retry_report
    unless @report.failed?
      render json: { error: "Este reporte no puede ser reintentado en su estado actual." },
             status: :unprocessable_entity
      return
    end

    if @report.report_type == "title_search"
      render json: { error: "Los reportes Title Search son gestionados manualmente por el equipo." },
             status: :unprocessable_entity
      return
    end

    @report.update!(status: "ordered", ordered_at: Time.current)
    ReportGenerationJob.perform_later(@report.id)

    render json: { report: report_json(@report) }, status: :ok
  end

  private

  def set_report
    @report = Report.find(params[:id])
    # Seguridad: el reporte debe pertenecer al usuario actual
    unless @report.user_id == current_user.id
      render json: { error: "No autorizado." }, status: :forbidden
    end
  end

  def report_json(report)
    {
      id:          report.id,
      report_type: report.report_type,
      type_label:  report.type_label,
      status:      report.status,
      has_pdf:     report.pdf_file.attached?,
      created_at:  report.created_at.strftime("%Y-%m-%d")
    }
  end
end
