class AddNotesToPipelineProperties < ActiveRecord::Migration[7.2]
  def change
    add_column :pipeline_properties, :notes, :text
  end
end
