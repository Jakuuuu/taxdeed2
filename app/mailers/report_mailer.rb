# frozen_string_literal: true

# ReportMailer — notificaciones al usuario relacionadas con sus reportes.
class ReportMailer < ApplicationMailer
  # Sent when an admin uploads and marks a Title Search report as generated.
  def title_search_ready(report)
    @report = report
    @user   = report.user
    @parcel = report.parcel

    mail(
      to:      @user.email,
      subject: "Your Title Search Report is Ready — #{@parcel&.address || "Your Property"}"
    )
  end
end
