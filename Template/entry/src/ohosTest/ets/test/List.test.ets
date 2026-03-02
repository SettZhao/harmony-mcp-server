import abilityTest from './Ability.test';
import usbSerialTest from './UsbSerial.test';

export default function testsuite() {
  abilityTest();
  usbSerialTest();
}