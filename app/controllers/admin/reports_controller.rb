# frozen_string_literal: true

# Admin::ReportsController — vista global de todos los reportes de la plataforma.
#
# Permite al equipo TSR:
#   - Ver todos los reportes (AVM, Property Scope, Title Search) con filtros
#   - Reintentar generación fallida (AVM + Scope solamente, Title Search se gestiona aparte)
#   - Marcar reportes como failed manualmente
#
class Admin::ReportsController < Admin::BaseController
  before_action :set_report, only: [:show, :retry, :mark_failed]

  # GET /admin/reports
  def index
    scope = Report.includes(:user, :parcel).order(created_at: :desc)
    scope = scope.where(report_type: params[:type])   if params[:type].present?
    scope = scope.where(status: params[:status])      if params[:status].present?

    @type_filter   = params[:type]
    @status_filter = params[:status]
    @reports = scope.page(params[:page]).per(30)

    @counts = {
      total:     Report.count,
      pending:   Report.where(status: :pending).count,
      ordered:   Report.where(status: :ordered).count,
      generated: Report.where(status: :generated).count,
      failed:    Report.where(status: :failed).count
    }
  end

  # GET /admin/reports/:id
  def show; end

  # POST /admin/reports/:id/retry
  # Re-queues generation for AVM / property_scope reports
  def retry
    if @report.title_search?
      return redirect_to admin_report_path(@report),
                         alert: "Title Searches cannot be auto-retried — use the Title Searches panel."
    end

    @report.update(status: :pending)
    ReportGenerationJob.perform_later(@report.id)
    redirect_to admin_report_path(@report), notice: "Report re-queued for generation."
  end

  # PATCH /admin/reports/:id/mark_failed
  def mark_failed
    if @report.update(status: :failed)
      redirect_to admin_report_path(@report), notice: "Report marked as failed."
    else
      redirect_to admin_report_path(@report), alert: "Could not update status."
    end
  end

  private

  def set_report
    @report = Report.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_reports_path, alert: "Report not found."
  end
end
