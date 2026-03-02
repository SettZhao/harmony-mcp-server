/**
 * Hex dump utility for debugging.
 * Ported from usb-serial-for-android (Android) to HarmonyOS ArkTS
 */

const HEX_DIGITS: string[] = [
  '0', '1', '2', '3', '4', '5', '6', '7',
  '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
];

export function dumpHexStringAll(array: Uint8Array): string {
  return dumpHexString(array, 0, array.length);
}

export function dumpHexString(array: Uint8Array, offset: number, length: number): string {
  let result = '';
  const line: number[] = new Array(16).fill(0);
  let lineIndex = 0;

  result += '\n0x';
  result += toHexStringNum(offset);

  for (let i = offset; i < offset + length; i++) {
    if (lineIndex === 16) {
      result += ' ';
      for (let j = 0; j < 16; j++) {
        const c = line[j];
        if (c > 0x20 && c < 0x7e) {
          result += String.fromCharCode(c);
        } else {
          result += '.';
        }
      }
      result += '\n0x';
      result += toHexStringNum(i);
      lineIndex = 0;
    }

    const b = array[i] & 0xFF;
    result += ' ';
    result += HEX_DIGITS[(b >>> 4) & 0x0F];
    result += HEX_DIGITS[b & 0x0F];
    line[lineIndex] = b;
    lineIndex++;
  }

  if (lineIndex !== 16) {
    const count = (16 - lineIndex) * 3 + 1;
    for (let i = 0; i < count; i++) {
      result += ' ';
    }
    for (let i = 0; i < lineIndex; i++) {
      const c = line[i];
      if (c > 0x20 && c < 0x7e) {
        result += String.fromCharCode(c);
      } else {
        result += '.';
      }
    }
  }

  return result;
}

export function toHexStringByte(b: number): string {
  return toHexStringArray(new Uint8Array([b & 0xFF]));
}

export function toHexStringArray(array: Uint8Array): string {
  return toHexStringRange(array, 0, array.length);
}

export function toHexStringRange(array: Uint8Array, offset: number, length: number): string {
  let buf = '';
  for (let i = offset; i < offset + length; i++) {
    const b = array[i] & 0xFF;
    buf += HEX_DIGITS[(b >>> 4) & 0x0F];
    buf += HEX_DIGITS[b & 0x0F];
  }
  return buf;
}

function toHexStringNum(n: number): string {
  const bytes = new Uint8Array(4);
  bytes[0] = (n >>> 24) & 0xFF;
  bytes[1] = (n >>> 16) & 0xFF;
  bytes[2] = (n >>> 8) & 0xFF;
  bytes[3] = n & 0xFF;
  return toHexStringArray(bytes);
}
