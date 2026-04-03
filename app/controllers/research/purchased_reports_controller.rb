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
        return render json: { error: "Invalid report type." }, status: :unprocessable_entity
      end

      # Idempotency — don't double-charge for already ordered/generated report
      existing = Report.for_parcel(parcel.id).by_type(report_type).where(user: current_user).first
      if existing && !existing.failed?
        return render json: { report: report_json(existing) }, status: :ok
      end

      subscription = current_user.subscription

      # Title Search: lifetime bonus — check differently
      if report_type == "title_search"
        unless subscription.can_use?(:title)
          return render json: { error: "Title Search is not included in your plan or has already been used." },
                        status: :payment_required
        end
      else
        unless subscription.can_use?(credit_key)
          return render json: {
            error: "You've reached your #{report_type.humanize} limit for this billing period.",
            limit: subscription.send("limit_#{credit_key}"),
            used:  subscription.send("used_#{credit_key}")
          }, status: :payment_required
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

      # TODO: ReportGenerationJob.perform_later(@report.id)

      render json: { report: report_json(@report) }, status: :created
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def report_json(report)
      {
        id:          report.id,
        report_type: report.report_type,
        type_label:  report.type_label,
        status:      report.status,
        file_url:    report.respond_to?(:file_url) ? report.file_url : nil,
        created_at:  report.created_at.strftime("%Y-%m-%d")
      }
    end
  end
end
