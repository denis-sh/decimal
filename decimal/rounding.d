﻿// Written in the D programming language

/**
 *
 * A D programming language implementation of the
 * General Decimal Arithmetic Specification,
 * Version 1.70, (25 March 2009).
 * (http://www.speleotrove.com/decimal/decarith.pdf)
 *
 * License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors: Paul D. Anderson
 */
/*          Copyright Paul D. Anderson 2009 - 2011.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE_1_0.txt or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */

module decimal.rounding;

import decimal.context;
import decimal.digits;
import decimal.decimal;
import std.array: insertInPlace;
import std.bigint;
import std.conv;
import std.ctype: isdigit;
import std.stdio: write, writeln;
import std.string;

unittest {
    writeln("---------------------");
    writeln("rounding......testing");
    writeln("---------------------");
}

//TODO: add ref context flags to parameters.
// UNREADY: round. Description. Private or public?
public void round(ref Decimal num, DecimalContext context) {

    if (!num.isFinite) return;

    // TODO: No! don't clear the flags!!! That's for the user to do.
    // context.clearFlags();
    // check for subnormal

    bool subnormal = false;
    if (num.isSubnormal()) {
        context.setFlag(SUBNORMAL);
        subnormal = true;
    }

    // check for overflow
    if (num.adjustedExponent > context.eMax) {
        context.setFlag(OVERFLOW);
        switch (context.mode) {
            case Rounding.HALF_UP:
            case Rounding.HALF_EVEN:
            case Rounding.HALF_DOWN:
            case Rounding.UP:
                bool sign = num.sign;
                num = Decimal.POS_INF;
                num.sign = sign;
                break;
            case Rounding.DOWN:
                bool sign = num.sign;
                num = Decimal.max;
                num.sign = sign;
                break;
            case Rounding.CEILING:
                if (num.sign) {
                    num = Decimal.max;
                    num.sign = true;
                }
                else {
                    num = Decimal.POS_INF;
                }
                break;
            case Rounding.FLOOR:
                if (num.sign) {
                    num = Decimal.NEG_INF;
                } else {
                    num = Decimal.max;
                }
                break;
        }
        context.setFlag(INEXACT);
        context.setFlag(ROUNDED);
        return;
    }
    roundByMode(num, context);
    // check for underflow
    if (num.isSubnormal /*&& num.isInexact*/) {
        context.setFlag(SUBNORMAL);
        int diff = context.eTiny - num.adjustedExponent;
        if (diff > num.digits) {
            num.mant = 0;
            num.expo = context.eTiny;
        } else if (diff > 0) {
            // TODO: do something about this
            writeln("We got a tiny one!");
        }
    }
    // check for zero
    if (num.sval == Decimal.SV.CLEAR && num.mant == BigInt(0)) {
        num.sval = Decimal.SV.ZERO;
        // subnormal rounding to zero == clamped
        // Spec. p. 51
        if (subnormal) {
            context.setFlag(CLAMPED);
        }
        return;
    }
} // end round()

unittest {
    write("round.........");
    Decimal before = Decimal(9999);
    Decimal after = before;
    pushPrecision;
    context.precision = 3;
    round(after, context);
    assert(after.toString() == "1.00E+4");
    before = Decimal(1234567890);
    after = before;
    context.precision = 3;
    round(after, context);;
    assert(after.toString() == "1.23E+9");
    after = before;
    context.precision = 4;
    round(after, context);;
    assert(after.toString() == "1.235E+9");
    after = before;
    context.precision = 5;
    round(after, context);;
    assert(after.toString() == "1.2346E+9");
    after = before;
    context.precision = 6;
    round(after, context);;
    assert(after.toString() == "1.23457E+9");
    after = before;
    context.precision = 7;
    round(after, context);;
    assert(after.toString() == "1.234568E+9");
    after = before;
    context.precision = 8;
    round(after, context);;
    assert(after.toString() == "1.2345679E+9");
    before = "1235";
    after = before;
    context.precision = 3;
    round(after, context);;
    assert(after.toAbstract() == "[0,124,1]");
    before = "12359";
    after = before;
    context.precision = 3;
    round(after, context);;
    assert(after.toAbstract() == "[0,124,2]");
    before = "1245";
    after = before;
    context.precision = 3;
    round(after, context);;
    assert(after.toAbstract() == "[0,124,1]");
    before = "12459";
    after = before;
    context.precision = 3;
    round(after, context);;
    assert(after.toAbstract() == "[0,125,2]");
    popPrecision;
    writeln("passed");
}

//--------------------------------
// private rounding routines
//--------------------------------

// UNREADY: shorten. Order. Unit tests.
/**
 * Clips the coefficient of the number to the specified precision.
 * Returns the (unsigned) remainder for adjustments based on rounding mode.
 * Sets the ROUNDED and INEXACT flags.
 */
private Decimal shorten(ref Decimal num, DecimalContext context) {
    Decimal remainder = Decimal.ZERO.dup;
    int diff = num.digits - context.precision;
    if (diff <= 0) {
        return remainder;
    }
    context.setFlag(ROUNDED);

    // the context can be zero when...??
    if (context.precision == 0) {
        num = num.sign ? Decimal.NEG_ZERO : Decimal.ZERO;
    } else {
        BigInt divisor = pow10(diff);
        BigInt dividend = num.mant;
        BigInt quotient = dividend/divisor;
        BigInt modulo = dividend - quotient*divisor;
        if (modulo != BigInt(0)) {
            remainder.digits = diff;
            remainder.expo = num.expo;
            remainder.mant = modulo;
            remainder.sval = Decimal.SV.CLEAR;
        }
        num.mant = quotient;
        num.digits = context.precision;
        num.expo += diff;
    }
    if (remainder != Decimal.ZERO) {
        context.setFlag(INEXACT);
    }

    return remainder;
}

unittest {
    writeln("shorten1......");
    Decimal num, acrem, exnum, exrem;
    num = Decimal(1234567890123456L);
    writeln("num = ", num);
    acrem = shorten(num, context);
    writeln("quo = ", num);
    writeln("rem = ", acrem);
    exnum = Decimal("1.2345E+15");
    assert(num == exnum);
    exrem = 67890123456;
    assert(acrem == exrem);
    writeln("passed");
}

// UNREADY: shorten. Order. Unit tests.
/**
 * Clips the coefficient of the number to the specified precision.
 * Returns the (unsigned) remainder for adjustments based on rounding mode.
 * Sets the ROUNDED and INEXACT flags.
 */
private ulong shorten(ref ulong num, ref uint digits, uint precision) {
    ulong remainder = 0;
    int diff = digits - precision;
    if (diff <= 0) {
        return remainder;
    }
    // if (remainder != 0) {...} ?
    //context.setFlag(ROUNDED);

    // TODO: This is a fictitious case .. the context can be zero when...??
    if (precision == 0) {
        num = 0;
    } else {
        ulong divisor = 10L^^diff;
        ulong dividend = num;
        ulong quotient = dividend / divisor;
        num = quotient;
        remainder = dividend - quotient*divisor;
        digits = precision;
    }
    // TODO: num.digits == precision.
    // TODO: num.expo == diff;
    return remainder;
}

unittest {
    writeln("shorten2......");
    ulong num, acrem, exnum, exrem;
    uint digits, precision;
    num = 1234567890123456L;
    digits = 16; precision = 5;
    writeln("num = ", num);
    acrem = shorten(num, digits, precision);
    writeln("quo = ", num);
    writeln("rem = ", acrem);
    exnum = 12345L;
//    assert(num == exnum);
    exrem = 67890123456L;
//    assert(acrem == exrem);
    writeln("passed");
    writeln("test missing");
}

// UNREADY: increment. Order.
/**
 * Increments the coefficient by 1. If this causes an overflow, divides by 10.
 */
private void increment(ref Decimal num) {
    num.mant += 1;
    // check if the num was all nines --
    // did the coefficient roll over to 1000...?
    Decimal test1 = Decimal(1, num.digits + num.expo);
    Decimal test2 = num;
    test2.digits++;
    int comp = decimal.arithmetic.compare(test1, test2, false);
    if (comp == 0) {
        num.digits++;
        // check if there are now too many digits...
        if (num.digits > context.precision) {
            round(num, context);
        }
    }
}

unittest {
    write("increment1....");
    Decimal num;
    Decimal expd;
    num = 10;
    expd = 11;
    increment(num);
    assert(num == expd);
    num = 19;
    expd = 20;
    increment(num);
    assert(num == expd);
    num = 999;
    expd = 1000;
    increment(num);
    assert(num == expd);
    writeln("passed");
}


/**
 * Increments the coefficient by 1.
 * Returns true if the increment resulted in
 * an increase in the number of digits;  i.e. input number was all 9s.
 */
private bool increment(ref ulong num) {
    uint digits = numDigits(num);
    num++;
    if (numDigits(num) > digits) {
        return true;
    }
    else {
        return false;
    }
}

unittest {
    write("increment2....");
    ulong num;
    ulong expd;
    num = 10;
    expd = 11;
    assert(!increment(num));
    assert(num == expd);
    num = 19;
    expd = 20;
    assert(!increment(num));
    assert(num == expd);
    num = 999;
    expd = 1000;
    assert(increment(num));
    assert(num == expd);
    writeln("passed");
}

/**
 * Detect whether T is a decimal type.
 */
template isDecimal(T) {
    enum bool isDecimal = is(T: Decimal);
}

unittest {
    write("isDecimal(T)..");
    writeln("test missing");
}

// UNREADY: roundByMode. Description. Order.
private void roundByMode(ref Decimal num, DecimalContext context) {
    Decimal remainder = shorten(num, context);

    // if the rounded flag is not set by the shorten operation, return
    if (!context.getFlag(ROUNDED)) {
        return;
    }
    // if the remainder is zero, return
    if (!context.getFlag(INEXACT)) {
        return;
    }

    switch (context.mode) {
        case Rounding.DOWN:
            return;
        case Rounding.HALF_UP:
            if (firstDigit(remainder.mant) >= 5) {
                increment(num);
            }
            return;
        case Rounding.HALF_EVEN:
            Decimal five = Decimal(5, remainder.digits + remainder.expo - 1);
            int result = decimal.arithmetic.compare(remainder, five, false);
            if (result > 0) {
                increment(num);
                return;
            }
            if (result < 0) {
                return;
            }
            // remainder == 5
            // if last digit is odd...
            if (lastDigit(num.mant) % 2) {
                increment(num);
            }
            return;
        case Rounding.CEILING:
            if (!num.sign && remainder != Decimal.ZERO) {
                increment(num);
            }
            return;
        case Rounding.FLOOR:
            if (num.sign && remainder != Decimal.ZERO) {
                increment(num);
            }
            return;
        case Rounding.HALF_DOWN:
            if (firstDigit(remainder.mant) > 5) {
                increment(num);
            }
            return;
        case Rounding.UP:
            if (remainder != Decimal.ZERO) {
                increment(num);
            }
            return;
    }    // end switch(mode)
} // end roundByMode()

unittest {
    write("roundByMode1..");
    writeln("test missing");
}

// UNREADY: roundByMode. Description. Order.
private uint roundByMode(ref long num, DecimalContext context) {

    uint digits = numDigits(num);
    ulong unum = std.math.abs(num);
    bool sign = num < 0;
    ulong remainder = shorten(unum, digits, context.precision);

//    writeln("remainder = ", remainder);

    // if the remainder is zero, return
    if (remainder == 0) {
        num = sign ? -unum : unum;
        return digits;
    }

    switch (context.mode) {
        case Rounding.DOWN:
            break;
        case Rounding.HALF_UP:
            if (firstDigit(remainder) >= 5) {
                if (increment(unum)) digits++;
            }
            break;
        case Rounding.HALF_EVEN:
            ulong first = firstDigit(remainder);
            if (first > 5) {
                if (increment(unum)) digits++;
            }
            if (first < 5) {
                break;
            }
            // remainder == 5
            // if last digit is odd...
            if (lastDigit(num) % 2) {
                if (increment(unum)) digits++;
            }
            break;
        case Rounding.CEILING:
            if (!sign && remainder != 0) {
                if (increment(unum)) digits++;
            }
            break;
        case Rounding.FLOOR:
            if (sign && remainder != 0) {
                if (increment(unum)) digits++;
            }
            break;
        case Rounding.HALF_DOWN:
            if (firstDigit(remainder) > 5) {
                if (increment(unum)) digits++;
            }
            break;
        case Rounding.UP:
            if (remainder != 0) {
                if (increment(unum)) digits++;
            }
            break;
    }    // end switch(mode)

    num = sign ? -unum : unum;
    return digits;

} // end roundByMode()

unittest {
    writeln("roundByMode2..");
    DecimalContext context;
    context.precision = 5;
    context.mode = Rounding.DOWN;
    long num; uint digits;
    num = 1000;
    context.mode = Rounding.DOWN;
    writeln("num = ", num, ", precision = ", context.precision, ", mode = ", context.mode.stringof);
    digits = roundByMode(num, context);
    writeln("num = ", num, ", digits = ", digits);
    num = 1000000;
    context.mode = Rounding.DOWN;
    writeln("num = ", num, ", precision = ", context.precision, ", mode = ", context.mode.stringof);
    digits = roundByMode(num, context);
    writeln("num = ", num, ", digits = ", digits);
    num = 1234550;
    context.mode = Rounding.DOWN;
    writeln("num = ", num, ", precision = ", context.precision, ", mode = ", context.mode.stringof);
    digits = roundByMode(num, context);
    writeln("num = ", num, ", digits = ", digits);
    num = 1234550;
    context.mode = Rounding.UP;
    writeln("num = ", num, ", precision = ", context.precision, ", mode = ", context.mode.stringof);
    digits = roundByMode(num, context);
    writeln("num = ", num, ", digits = ", digits);
    num = 1234550;
    context.mode = Rounding.FLOOR;
    writeln("num = ", num, ", precision = ", context.precision, ", mode = ", context.mode.stringof);
    digits = roundByMode(num, context);
    writeln("num = ", num, ", digits = ", digits);
    num = 1234550;
    context.mode = Rounding.CEILING;
    writeln("num = ", num, ", precision = ", context.precision, ", mode = ", context.mode.stringof);
    digits = roundByMode(num, context);
    writeln("num = ", num, ", digits = ", digits);
    num = 19999999;
    context.mode = Rounding.DOWN;
    writeln("num = ", num, ", precision = ", context.precision, ", mode = ", context.mode.stringof);
    digits = roundByMode(num, context);
    writeln("num = ", num, ", digits = ", digits);
    writeln("test missing");
}

unittest {
    writeln("---------------------");
    writeln("rounding.....finished");
    writeln("---------------------");
    writeln();
}


