class MakeDanielAdmin < ActiveRecord::Migration[7.2]
  def up
    user = User.find_by(email: 'danielantonio1918@gmail.com')
    if user
      user.update!(admin: true)
      puts "Migrated: danielantonio1918@gmail.com is now an admin."
    else
      puts "User danielantonio1918@gmail.com not found!"
    end
  end

  def down
    user = User.find_by(email: 'danielantonio1918@gmail.com')
    if user
      user.update!(admin: false)
    end
  end
end
