# cover android sdk api by swift-java

use swift-java to handle different parts of the android sdk
when nucleantui is doing android application
but for now just leave nucleantui out of it..

its prime job is just to give us a swift api version of the different apis like camera, flash light, access to photoes

but as seperate targets for each thing.. 

then later we can make one for ios/ macos and combine both to cover same things by same api on both sides..

for now just make sure we use same version as NucleantApplication

reason why no nucleantui yet is because it requires vulkan and dont want to boot linux to enable emulator with acceleration for vulkan..


sooo seems easier just to test it for now with kotlin / nativeui calling the swift api.. 

just something simple that allows us to tests what is possible by emulator..