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

module decimal.conv;

import decimal.dec32;
import decimal.decimal;
import std.array: insertInPlace;
import std.bigint;
import std.bitmanip;
import std.conv;
import std.stdio;
import std.string;

unittest {
    writeln("---------------------");
    writeln("conv..........testing");
    writeln("---------------------");
}

//--------------------------------
//  conversions
//--------------------------------

/**
 * Temporary hack to allow to!string(BigInt).
 */
T to(T:string)(const int n) {
    return format("%d", n);
}

/**
 * Temporary hack to allow to!string(BigInt).
 */
T to(T:string)(const BigInt num) {
    string outbuff="";
    void sink(const(char)[] s) { outbuff ~= s; }
    num.toString(&sink, "d");
    return outbuff;
}

/**
 * Converts a small decimal to a big decimal
 */
public BigDecimal toDecimal(T)(const T num) if (isSmallDecimal!T) {
    bool sign = num.sign;
    auto mant = num.coefficient;
    int  expo = num.exponent;

    if (num.isFinite) {
        return BigDecimal(sign, BigInt(mant), expo);
    }
    else if (num.isInfinite) {
        return BigDecimal(sign, "Inf", 0);
    }
    else if (num.isQuiet) {
        return BigDecimal(sign, "qNaN", mant);
    }
    else if (num.isSignaling) {
        return BigDecimal(sign, "sNaN", mant);
    }

    // NOTE: Should never reach here.
    throw (new Exception("Invalid conversion"));

}

unittest {
    write("toDecimal...");
    Dec32 small;
    BigDecimal big;
    big = toDecimal!Dec32(small);
    writeln();
    writeln("big = ", big);
    writeln("test missing");
}

/**
 * Converts an encoded decimal number to a hexadecimal string
 */
public string toHexString(T)(const T num) if (isSmallDecimal!T) {
    // TODO: what's the syntax for a variable format string?
    return format("0x%016X", value);
}

unittest {
    write("toHexString...");
    writeln("test missing");
}

/**
 * Detect whether T is a decimal type.
 */
template isDecimal(T) {
    enum bool isDecimal = is(T: Dec32) || is(T: BigDecimal);
}

unittest {
    write("isDecimal(T)...");
    writeln("test missing");
}

/**
 * Detect whether T is a decimal type.
 */
template isBigDecimal(T) {
    enum bool isBigDecimal = is(T: BigDecimal);
}

unittest {
    write("isBigDecimal(T)...");
    writeln("test missing");
}

/**
 * Detect whether T is a decimal type.
 */
template isSmallDecimal(T) {
    enum bool isSmallDecimal = is(T: Dec32); // || is(T: Dec64);
}

unittest {
    write("isSmallDecimal(T)...");
    writeln("test missing");
}

/*unittest
{
    static assert(isIntegral!(byte));
    static assert(isIntegral!(const(byte)));
    static assert(isIntegral!(immutable(byte)));
    static assert(isIntegral!(shared(byte)));
    static assert(isIntegral!(shared(const(byte))));
}*/


// UNREADY: toSciString. Description. Unit Tests.
/**
    * Converts a BigDecimal number to a string representation.
    */
public string toSciString(T)(const T num) if (isDecimal!T) {

    auto mant = num.coefficient;
    int  expo = num.exponent;
    bool signed = num.isSigned;

    // string representation of special values
    if (num.isSpecial) {
        string str;
        if (num.isInfinite) {
            str = "Infinity";
        }
        else if (num.isSignaling) {
            str = "sNaN";
        }
        else {
            str = "NaN";
        }
        // add payload to NaN, if present
        if (num.isNaN && mant != 0) {
            str ~= to!string(mant);
        }
        // add sign, if present
        return signed ? "-" ~ str : str;
    }

    // string representation of finite numbers
    string temp = to!string(mant);
    char[] cstr = temp.dup;
    int clen = cstr.length;
    int adjx = expo + clen - 1;

    // if exponent is small, don't use exponential notation
    if (expo <= 0 && adjx >= -6) {
        // if exponent is not zero, insert a decimal point
        if (expo != 0) {
            int point = std.math.abs(expo);
            // if coefficient is too small, pad with zeroes
            if (point > clen) {
                cstr = zfill(cstr, point);
                clen = cstr.length;
            }
            // if no chars precede the decimal point, prefix a zero
            if (point == clen) {
                cstr = "0." ~ cstr;
            }
            // otherwise insert a decimal point
            else {
                insertInPlace(cstr, cstr.length - point, ".");
            }
        }
        return signed ? ("-" ~ cstr).idup : cstr.idup;
    }
    // use exponential notation
    if (clen > 1) {
        insertInPlace(cstr, 1, ".");
    }
    string xstr = to!string(adjx);
    if (adjx >= 0) {
        xstr = "+" ~ xstr;
    }
    string str = (cstr ~ "E" ~ xstr).idup;
    return signed ? "-" ~ str : str;

};    // end toSciString()

unittest {
    write("toSciString...");
    BigDecimal num = BigDecimal(123); //(false, 123, 0);
    assert(toSciString!BigDecimal(num) == "123");
    assert(num.toAbstract() == "[0,123,0]");
    num = BigDecimal(-123, 0);
    assert(toSciString!BigDecimal(num) == "-123");
    assert(num.toAbstract() == "[1,123,0]");
    num = BigDecimal(123, 1);
    assert(toSciString!BigDecimal(num) == "1.23E+3");
    assert(num.toAbstract() == "[0,123,1]");
    num = BigDecimal(123, 3);
    assert(toSciString!BigDecimal(num) == "1.23E+5");
    assert(num.toAbstract() == "[0,123,3]");
    num = BigDecimal(123, -1);
    assert(toSciString!BigDecimal(num) == "12.3");
    assert(num.toAbstract() == "[0,123,-1]");
    num = BigDecimal(123, -5);
    assert(toSciString!BigDecimal(num) == "0.00123");
    assert(num.toAbstract() == "[0,123,-5]");
    num = BigDecimal(123, -10);
    assert(toSciString!BigDecimal(num) == "1.23E-8");
    assert(num.toAbstract() == "[0,123,-10]");
    num = BigDecimal(-123, -12);
    assert(toSciString!BigDecimal(num) == "-1.23E-10");
    assert(num.toAbstract() == "[1,123,-12]");
    num = BigDecimal(0, 0);
    assert(toSciString!BigDecimal(num) == "0");
    assert(num.toAbstract() == "[0,0,0]");
    num = BigDecimal(0, -2);
    assert(toSciString!BigDecimal(num) == "0.00");
    assert(num.toAbstract() == "[0,0,-2]");
    num = BigDecimal(0, 2);
    assert(toSciString!BigDecimal(num) == "0E+2");
    assert(num.toAbstract() == "[0,0,2]");
    num = -BigDecimal(0, 0);
    assert(toSciString!BigDecimal(num) == "-0");
    assert(num.toAbstract() == "[1,0,0]");
    num = BigDecimal(5, -6);
    assert(toSciString!BigDecimal(num) == "0.000005");
    assert(num.toAbstract() == "[0,5,-6]");
    num = BigDecimal(50,-7);
    assert(toSciString!BigDecimal(num) == "0.0000050");
    assert(num.toAbstract() == "[0,50,-7]");
    num = BigDecimal(5, -7);
    assert(toSciString!BigDecimal(num) == "5E-7");
    assert(num.toAbstract() == "[0,5,-7]");
    num = BigDecimal("inf");
    assert(toSciString!BigDecimal(num) == "Infinity");
    assert(num.toAbstract() == "[0,inf]");
    num = BigDecimal(true, "inf");
    assert(toSciString!BigDecimal(num) == "-Infinity");
    assert(num.toAbstract() == "[1,inf]");
    num = BigDecimal(false, "NaN");
    assert(toSciString!BigDecimal(num) == "NaN");
    assert(num.toAbstract() == "[0,qNaN]");
    num = BigDecimal(false, "NaN", 123);
    assert(toSciString!BigDecimal(num) == "NaN123");
    assert(num.toAbstract() == "[0,qNaN,123]");
    num = BigDecimal(true, "sNaN");
    assert(toSciString!BigDecimal(num) == "-sNaN");
    assert(num.toAbstract() == "[1,sNaN]");
    writeln("passed");
}

// UNREADY: toEngString. Description. Unit Tests.
/**
    * Converts a BigDecimal number to a string representation.
    */
public string toEngString(T)(const T num) if (isDecimal!T) {

    auto mant = num.coefficient;
    int  expo = num.exponent;
    bool signed = num.isSigned;

    // string representation of special values
    if (num.isSpecial) {
        string str;
        if (num.isInfinite) {
            str = "Infinity";
        }
        else if (num.isSignaling) {
            str = "sNaN";
        }
        else {
            str = "NaN";
        }
        // add payload to NaN, if present
        if (num.isNaN && mant != 0) {
            str ~= to!string(mant);
        }
        // add sign, if present
        return signed ? "-" ~ str : str;
    }

    // string representation of finite numbers
    string temp = to!string(mant);
    char[] cstr = temp.dup;
    int clen = cstr.length;
    int adjx = expo + clen - 1;

    // if exponent is small, don't use exponential notation
    if (expo <= 0 && adjx >= -6) {
        // if exponent is not zero, insert a decimal point
        if (expo != 0) {
            int point = std.math.abs(expo);
            // if coefficient is too small, pad with zeroes
            if (point > clen) {
                cstr = zfill(cstr, point);
                clen = cstr.length;
            }
            // if no chars precede the decimal point, prefix a zero
            if (point == clen) {
                cstr = "0." ~ cstr;
            }
            // otherwise insert a decimal point
            else {
                insertInPlace(cstr, cstr.length - point, ".");
            }
        }
        return signed ? ("-" ~ cstr).idup : cstr.idup;
    }

    // use exponential notation
    if (num.isZero) {
        adjx += 2;
    }

    int mod = adjx % 3;
    // the % operator rounds down; we need it to round to floor.
    if (mod < 0) {
        mod = -(mod + 3);
    }

    int dot = std.math.abs(mod) + 1;
    adjx = adjx - dot + 1;

    if (num.isZero) {
        dot = 1;
        clen = 3 - std.math.abs(mod);
        cstr.length = 0;
        for (int i = 0; i < clen; i++) {
            cstr ~= '0';
        }
    }

    while (dot > clen) {
        cstr ~= '0';
        clen++;
    }
    if (clen > dot) {
        insertInPlace(cstr, dot, ".");
    }
    string str = cstr.idup;
    if (adjx != 0) {
        string xstr = to!string(adjx);
        if (adjx > 0) {
            xstr = '+' ~ xstr;
        }
        str = str ~ "E" ~ xstr;
    }
    return signed ? "-" ~ str : str;

};    // end toEngString()

unittest {
    write("toEngString...");
    string str = "1.23E+3";
    BigDecimal num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "123E+3";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "12.3E-9";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "-123E-12";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "700E-9";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "70";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0E-9";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.00E-6";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.0E-6";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.000000";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
/*    str = "0.00E-3";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.0E-3";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);*/
    str = "0.000";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.00";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.0";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.00E+3";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.0E+3";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0E+3";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.00E+6";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.0E+6";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0E+6";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    str = "0.00E+9";
    num = BigDecimal(str);
    assert(toEngString!BigDecimal(num) == str);
    writeln("passed");
}

unittest {
/*    writefln("num.mant = 0x%08X", num.mant);
    writefln("max_mant = 0x%08X", Dec32.max_mant);
    writefln("max_norm = 0x%08X", Dec32.max_norm);
    writeln("max_expo = ", Dec32.max_expo);
    writeln("min_expo = ", Dec32.min_expo);

    writefln("qnan_val = 0x%08X", Dec32.qnan_val);
    writeln("Dec32.qNaN = ", Dec32.qNaN);

    Dec32 dec = Dec32();
    writeln("dec = ", dec);
    writeln("dec.mant1 = ", dec.mant1);

    BigDecimal num = BigDecimal(0);
    dec = Dec32(num);
    writeln("num = ", num);
    writeln("dec = ", dec);

    num = BigDecimal(1);
    dec = Dec32(num);
    writeln("num = ", num);
    writeln("dec = ", dec);

    num = BigDecimal(-1);
    dec = Dec32(num);
    writeln("num = ", num);
    writeln("dec = ", dec);

    num = BigDecimal(-16000);
    dec = Dec32(num);
    writeln("num = ", num);
    writeln("dec = ", dec);

    num = BigDecimal(uint.max);
    dec = Dec32(num);
    writeln("num = ", num);
    writeln("dec = ", dec);*/
}

unittest {
    writeln("----------------------");
    writeln("conv..........finished");
    writeln("----------------------");
}


