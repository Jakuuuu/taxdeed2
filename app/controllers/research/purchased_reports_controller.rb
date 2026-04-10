# frozen_string_literal: true

module Research
  class PurchasedReportsController < BaseController
    CREDIT_MAP = {
      "avm"            => :avm,
      "property_scope" => :scope,
      "title_search"   => :title
    }.freeze

    def index
      # Tab 1: Parcel Reports
      @reports = Report.where(user: current_user)
                       .includes(parcel: :auction)
                       .latest_first
                       .page(params[:page]).per(25)

      # Tab 2: Prior Sale Results — viewed parcels from completed auctions
      @prior_sales = ViewedParcel.where(user: current_user)
                                 .joins(parcel: :auction)
                                 .where(auctions: { status: "completed" })
                                 .includes(parcel: :auction)
                                 .order(created_at: :desc)
                                 .page(params[:page]).per(25)

      # Tab 3: Viewed Parcels this cycle
      @viewed_parcels = ViewedParcel.where(user: current_user)
                                    .includes(parcel: :auction)
                                    .order(created_at: :desc)
                                    .page(params[:page]).per(25)

      @active_tab = params[:tab] || "reports"
    end

    def create
      parcel      = Parcel.find(params[:parcel_id])
      report_type = params[:report_type].to_s.strip
      credit_key  = CREDIT_MAP[report_type]

      unless Report::VALID_TYPES.include?(report_type) && credit_key
        respond_to do |format|
          format.html { redirect_back fallback_location: research_purchased_reports_path, alert: "Invalid report type." }
          format.json { render json: { error: "Invalid report type." }, status: :unprocessable_entity }
        end
        return
      end

      # Idempotency — don't double-charge for already ordered/generated report
      existing = Report.for_parcel(parcel.id).by_type(report_type).where(user: current_user).first
      if existing && !existing.failed?
        respond_to do |format|
          format.html { redirect_back fallback_location: research_purchased_reports_path, notice: "Report already exists." }
          format.json { render json: { report: report_json(existing) }, status: :ok }
        end
        return
      end

      subscription = current_user.subscription

      # Title Search: lifetime bonus — check differently
      if report_type == "title_search"
        unless subscription.can_use?(:title)
          respond_to do |format|
            format.html { redirect_back fallback_location: research_purchased_reports_path, alert: "Title Search is not included in your plan or has already been used." }
            format.json { render json: { error: "Title Search is not included in your plan or has already been used." }, status: :payment_required }
          end
          return
        end
      else
        unless subscription.can_use?(credit_key)
          respond_to do |format|
            format.html { redirect_back fallback_location: research_purchased_reports_path, alert: "You've reached your limit." }
            format.json { render json: { error: "Limit reached", limit: subscription.send("limit_#{credit_key}"), used: subscription.send("used_#{credit_key}") }, status: :payment_required }
          end
          return
        end
      end

      ActiveRecord::Base.transaction do
        subscription.increment_usage!(credit_key)
        @report = (existing || Report.new).tap do |r|
          r.user        = current_user
          r.parcel      = parcel
          r.report_type = report_type
          r.status      = "ordered"
          r.save!
        end
      end

      # Lanzar job sólo para tipos automáticos (no title_search)
      unless report_type == "title_search"
        ReportGenerationJob.perform_later(@report.id)
      end

      respond_to do |format|
        format.html do
          redirect_back fallback_location: research_purchased_reports_path, notice: "Report ordered successfully."
        end
        format.json { render json: { report: report_json(@report) }, status: :created }
      end
    rescue => e
      respond_to do |format|
        format.html do
          redirect_back fallback_location: research_purchased_reports_path, alert: e.message
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end

    private

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
end

