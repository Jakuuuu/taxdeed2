# frozen_string_literal: true

# Admin::TitleSearchesController — gestión del ciclo de vida de reportes Title Search.
#
# Flujo operativo:
#   1. Usuario solicita Title Search → Report creado con status: 'ordered'
#   2. Admin ve la lista aquí, va al detalle, añade notas + referencia DataTrace
#   3. Admin sube PDF → mark_generated → status: 'generated', email al usuario
#   4. Si DataTrace falla → mark_failed → status: 'failed'
#
class Admin::TitleSearchesController < Admin::BaseController
  before_action :set_report, only: [:show, :update, :mark_generated, :mark_failed]

  # GET /admin/title_searches
  def index
    scope = Report.title_search.includes(:user, :parcel).order(created_at: :asc)

    scope = scope.where(status: params[:status]) if params[:status].present?

    @status_filter = params[:status]
    @counts = {
      all:           Report.title_search.count,
      ordered:       Report.title_search.where(status: :ordered).count,
      generated:     Report.title_search.where(status: :generated).count,
      failed:        Report.title_search.where(status: :failed).count,
      revenue_cents: Report.title_search.where(payment_status: "paid").sum(:amount_cents)
    }
    @reports = scope.page(params[:page]).per(25)
  end

  # GET /admin/title_searches/:id
  def show; end

  # PATCH /admin/title_searches/:id
  # Saves admin_notes and datatrace_order_ref without changing status
  def update
    if @report.update(admin_fields_params)
      redirect_to admin_title_search_path(@report), notice: "Notes saved."
    else
      flash.now[:alert] = "Error saving: #{@report.errors.full_messages.to_sentence}"
      render :show, status: :unprocessable_entity
    end
  end

  # PATCH /admin/title_searches/:id/mark_generated
  # Uploads PDF + marks report as generated + notifies user
  def mark_generated
    if params[:pdf_file].blank?
      return redirect_to admin_title_search_path(@report),
                         alert: "Please attach a PDF before marking as generated."
    end

    @report.pdf_file.attach(params[:pdf_file])

    unless @report.pdf_file.attached?
      return redirect_to admin_title_search_path(@report),
                         alert: "Failed to attach the PDF. Please try again."
    end

    # Save any notes/ref before changing status
    @report.assign_attributes(admin_fields_params) if params[:report].present?

    if @report.update(status: :generated, generated_at: Time.current)
      ReportMailer.title_search_ready(@report).deliver_later
      redirect_to admin_title_search_path(@report),
                  notice: "Report marked as Generated. Email notification sent to #{@report.user.email}."
    else
      redirect_to admin_title_search_path(@report),
                  alert: "Could not update status: #{@report.errors.full_messages.to_sentence}"
    end
  end

  # PATCH /admin/title_searches/:id/mark_failed
  def mark_failed
    if @report.update(status: :failed)
      redirect_to admin_title_search_path(@report),
                  notice: "Report marked as Failed."
    else
      redirect_to admin_title_search_path(@report),
                  alert: "Could not mark as failed: #{@report.errors.full_messages.to_sentence}"
    end
  end

  private

  def set_report
    @report = Report.title_search.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_title_searches_path, alert: "Report not found."
  end

  def admin_fields_params
    params.require(:report).permit(:admin_notes, :datatrace_order_ref)
  end
end
