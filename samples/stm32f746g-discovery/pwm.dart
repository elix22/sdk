import 'dart:dartino';
import 'package:stm32/stm32f746g_disco.dart';
import 'package:stm32/gpio.dart';

main() {
  STM32F746GDiscovery board = new STM32F746GDiscovery();
  STM32Gpio gpio = board.gpio;
  // Initialize all PWM pins
  var pins = [
    gpio.initPwmOutput(STM32F746GDiscovery.D3),
    gpio.initPwmOutput(STM32F746GDiscovery.D5),
    gpio.initPwmOutput(STM32F746GDiscovery.D6),
    gpio.initPwmOutput(STM32F746GDiscovery.D9),
    gpio.initPwmOutput(STM32F746GDiscovery.D10),
    gpio.initPwmOutput(STM32F746GDiscovery.D11)
  ];
  // Set different frequences on each pin.
  // Note: these that share a timer will share the frequency.
  for(int i = 0; i < pins.length; i++){
    pins[i].prescaler = (i + 1) * 100 - 1;
    pins[i].period = 9999;
    pins[i].output(i * 1000 + 1000);
  }
  while(true){
    sleep(1);
  }
}
