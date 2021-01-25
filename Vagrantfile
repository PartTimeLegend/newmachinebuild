Vagrant.configure("2") do |config|
  config.vm.define "test" do |test|
    test.vm.box = "gusztavvargadr/windows-10"
    test.vm.hostname = "test"
    test.vm.provision "shell", privileged: "true", powershell_elevated_interactive: "true", path: "BaseMachineSetup.ps1"
  end
end
