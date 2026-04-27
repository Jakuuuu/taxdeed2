# frozen_string_literal: true

# ReportGenerationJob
# ══════════════════════════════════════════════════════════════════════════
# NOTA: Este job es LEGACY y actualmente no se invoca.
#
# El Property Intelligence Report (ficha) se genera SÍNCRONAMENTE en
# ParcelsController#download_pdf — no pasa por este job.
#
# Title Search se gestiona manualmente desde el panel Admin.
#
# Este job se mantiene como infraestructura para posibles futuros
# reportes que requieran generación asíncrona (ej. reportes pesados
# con imágenes o datos de terceros).
# ══════════════════════════════════════════════════════════════════════════
class ReportGenerationJob < ApplicationJob
  queue_as :reports

  # No silenciar errores — queremos que Sidekiq los registre
  discard_on(ActiveRecord::RecordNotFound)

  def perform(report_id)
    report = Report.includes(parcel: [:parcel_liens, :auction]).find(report_id)

    # Title Search se gestiona manualmente — no auto-generar
    return if report.report_type == "title_search"

    # Si ya se generó (posible duplicado de job), salir
    return if report.generated?

    # Marcar como en proceso
    report.update!(status: "ordered", ordered_at: Time.current)

    begin
      # Generar PDF con datos de la BD
      pdf = ReportPdfBuilder.build(parcel: report.parcel)

      # Adjuntar a Active Storage
      filename = "PropertyIntelligence_#{report.parcel.parcel_id}_#{Date.today}.pdf"
                 .gsub(/[^a-zA-Z0-9_\-.]/, "_")

      report.pdf_file.attach(
        io:           StringIO.new(pdf.render),
        filename:     filename,
        content_type: "application/pdf"
      )

      # Marcar como generado
      report.update!(status: "generated", generated_at: Time.current)

      Rails.logger.info "[ReportGenerationJob] Report ##{report.id} generated successfully."

    rescue StandardError => e
      Rails.logger.error "[ReportGenerationJob] Report ##{report.id} FAILED: #{e.message}"
      report.update!(status: "failed")
      raise e  # Re-raise para que Sidekiq registre y reintente según su política
    end
  end
end
