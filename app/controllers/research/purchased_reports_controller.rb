# frozen_string_literal: true

module Research
  class PurchasedReportsController < BaseController
    CREDIT_MAP = {
      "avm"            => :avm,
      "property_scope" => :scope,
      "title_search"   => :title
    }.freeze

    def index
      @reports = Report.where(user: current_user)
                       .includes(:parcel)
                       .latest_first
                       .page(params[:page]).per(25)
    end

    def create
      parcel      = Parcel.find(params[:parcel_id])
      report_type = params[:report_type].to_s.strip
      credit_key  = CREDIT_MAP[report_type]

      unless Report::VALID_TYPES.include?(report_type) && credit_key
        return render json: { error: "Invalid report type." }, status: :unprocessable_entity
      end

      # Idempotency — don't double-charge if already ordered
      existing = Report.for_parcel(parcel.id).by_type(report_type).where(user: current_user).first
      if existing
        return render json: { report: report_json(existing) }, status: :ok
      end

      subscription = current_user.subscription

      # Title Search is a lifetime bonus — handled separately
      if report_type == "title_search"
        unless subscription.can_use?(:title)
          return render json: { error: "Title Search not included in your plan or already used." },
                        status: :payment_required
        end
      else
        unless subscription.can_use?(credit_key)
          return render json: { error: "You've reached your #{report_type.humanize} limit for this billing period." },
                        status: :payment_required
        end
      end

      ActiveRecord::Base.transaction do
        subscription.increment_usage!(credit_key)
        @report = Report.create!(
          user:        current_user,
          parcel:      parcel,
          report_type: report_type,
          status:      "ordered"
        )
      end

      render json: { report: report_json(@report) }, status: :created
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def report_json(report)
      {
        id:          report.id,
        report_type: report.report_type,
        status:      report.status,
        file_url:    report.respond_to?(:file_url) ? report.file_url : nil,
        created_at:  report.created_at.strftime("%Y-%m-%d")
      }
    end
  end
end
