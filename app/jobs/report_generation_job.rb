# frozen_string_literal: true

# ReportGenerationJob
# Genera el PDF de un reporte AVM o Property Scope y lo adjunta via Active Storage.
# Sólo aplica para report_type avm y property_scope.
# Title Search se gestiona manualmente desde el panel Admin.
#
# Uso:
#   ReportGenerationJob.perform_later(report.id)
class ReportGenerationJob < ApplicationJob
  queue_as :reports

  # No silenciar errores — queremos que Sidekiq los registre
  discard_on(ActiveRecord::RecordNotFound)

  def perform(report_id)
    report = Report.includes(parcel: [:parcel_liens, :auction]).find(report_id)

    # Sólo procesamos tipos automáticos
    return if report.report_type == "title_search"

    # Si ya se generó (posible duplicado de job), salir
    return if report.generated?

    # Marcar como en proceso
    report.update!(status: "ordered", ordered_at: Time.current)

    begin
      # 1. Generar PDF con datos de la BD
      pdf = ReportPdfBuilder.build(
        report_type: report.report_type,
        parcel:      report.parcel
      )

      # 2. Adjuntar a Active Storage
      filename = "#{report.report_type}_#{report.parcel.parcel_id}_#{Date.today}.pdf"
                 .gsub(/[^a-zA-Z0-9_\-.]/, "_")

      report.pdf_file.attach(
        io:           StringIO.new(pdf.render),
        filename:     filename,
        content_type: "application/pdf"
      )

      # 3. Marcar como generado
      report.update!(status: "generated", generated_at: Time.current)

      Rails.logger.info "[ReportGenerationJob] Report ##{report.id} (#{report.report_type}) generated successfully."

    rescue StandardError => e
      Rails.logger.error "[ReportGenerationJob] Report ##{report.id} FAILED: #{e.message}"
      report.update!(status: "failed")
      raise e  # Re-raise para que Sidekiq registre y reintente según su política
    end
  end
end
