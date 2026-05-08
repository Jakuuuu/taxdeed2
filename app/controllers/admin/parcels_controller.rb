# frozen_string_literal: true

module Admin
  # Admin::ParcelsController
  # --------------------------------------------------------------------
  # Permite a administradores listar parcels (paginado, filtrable) y
  # SOBRE-ESCRIBIR el clear_to_bid_grade manualmente. Cualquier cambio
  # se registra en logs estructurados (`[ADMIN_OVERRIDE:CTB_GRADE]`)
  # para trazabilidad.
  #
  # GAP DOCUMENTADO: AdminAuditLog actualmente requiere `target_user_id`
  # (schema diseñado para acciones sobre cuentas). Para evitar
  # contaminar la semántica, el override de grade se registra solo
  # como log estructurado hasta que exista una tabla AdminAuditEvent
  # genérica. Ver software/rules/clear_to_bid/admin_override.md.
  #
  # Whitelist de campos editables: SOLO clear_to_bid_grade. Cualquier
  # otro campo viene del sync de Sheets (Espejo Infalible).
  # --------------------------------------------------------------------
  class ParcelsController < Admin::BaseController
    before_action :set_parcel, only: [:update]

    PAGE_SIZE = 50

    def index
      @parcels = Parcel.all
      @parcels = @parcels.by_state(params[:state])               if params[:state].present?
      @parcels = @parcels.by_county(params[:county])             if params[:county].present?
      @parcels = @parcels.by_clear_to_bid_grade(params[:grade])  if params[:grade].present?
      @parcels = @parcels.search_text(params[:q])                if params[:q].present?

      # Si el filtro :clear_to_bid presente → solo viable+optimo
      @parcels = @parcels.clear_to_bid if params[:clear_to_bid].present?

      @parcels = @parcels.order(updated_at: :desc).limit(PAGE_SIZE)
      @grades  = Parcel::CLEAR_TO_BID_GRADES
    end

    def update
      old_grade  = @parcel.clear_to_bid_grade
      old_locked = @parcel.clear_to_bid_grade_locked?
      raw_grade  = parcel_params[:clear_to_bid_grade]
      new_grade  = raw_grade.presence # "" → nil
      # Checkbox: no checked → param ausente → preserva valor actual a falso.
      new_locked = ActiveModel::Type::Boolean.new.cast(parcel_params[:clear_to_bid_grade_locked])

      if new_grade.present? && !Parcel::CLEAR_TO_BID_GRADES.include?(new_grade)
        return respond_invalid("Grade inválido: #{raw_grade.inspect}")
      end

      if old_grade == new_grade && old_locked == new_locked
        respond_to do |format|
          format.html { redirect_to admin_parcels_path, notice: "Sin cambios." }
          format.json { render json: { ok: true, unchanged: true, parcel_id: @parcel.id } }
        end
        return
      end

      @parcel.update!(
        clear_to_bid_grade:        new_grade,
        clear_to_bid_grade_locked: new_locked
      )

      Rails.logger.tagged("ADMIN_OVERRIDE", "CTB_GRADE") do
        Rails.logger.info(
          "admin_user_id=#{current_user.id} " \
          "parcel_id=#{@parcel.id} " \
          "field=clear_to_bid_grade " \
          "old_grade=#{old_grade.inspect} " \
          "new_grade=#{new_grade.inspect} " \
          "old_locked=#{old_locked} " \
          "new_locked=#{new_locked} " \
          "ip=#{request.remote_ip}"
        )
      end

      respond_to do |format|
        format.html { redirect_to admin_parcels_path, notice: "Clear-to-Bid grade actualizado." }
        format.json { render json: { ok: true, parcel_id: @parcel.id, clear_to_bid_grade: new_grade, clear_to_bid_grade_locked: new_locked } }
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_invalid(e.message)
    end

    private

    def set_parcel
      @parcel = Parcel.find(params[:id])
    end

    # Whitelist ESTRICTA: solo clear_to_bid_grade y su lock son editables por admin.
    # Cualquier otro campo viene del sync de Google Sheets (Espejo Infalible).
    def parcel_params
      params.require(:parcel).permit(:clear_to_bid_grade, :clear_to_bid_grade_locked)
    end

    def respond_invalid(message)
      respond_to do |format|
        format.html { redirect_to admin_parcels_path, alert: "Error: #{message}" }
        format.json { render json: { ok: false, error: message }, status: :unprocessable_entity }
      end
    end
  end
end
