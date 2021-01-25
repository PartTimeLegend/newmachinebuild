Vagrant.configure("2") do |config|
  config.vm.box = "gusztavvargadr/windows-10"
  config.vm.provision "shell" do |s|
  dir = File.expand_path("..", __FILE__)
  puts "DIR: #{dir}"

  config.vm.provision "shell", path: File.join(dir, "BaseMachineSetup.ps1")
  end 
end
