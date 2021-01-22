Vagrant.configure("2") do |config|
  config.vm.box = "gusztavvargadr/windows-10"
  config.vm.provision "shell" do |s|
    p = File.expand_path("../", __FILE__)
    s.path = p + "\\BaseMachineSetup.ps1"
  end 
end