﻿// Written in the D programming language

/**
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

module decimal.dec32;

import std.array: insertInPlace;
import std.bigint;
import std.bitmanip;
import std.conv;
import std.stdio;
import std.string;

import decimal.arithmetic;
import decimal.context;
import decimal.decimal;
import decimal.rounding;

// (2) TODO: toInt, toLong.
// (3) TODO: digits(uint).
// (4) TODO: problem with unary ops (++).
// (5) TODO: subnormal creation.
// (6) TODO: all others can wait.
// (7) TODO: when all are copied, delete this.
unittest {
    writeln("---------------------");
    writeln("decimal32.......begin");
    writeln("---------------------");
}

struct Dec32 {

    /// The global context for this type.
    private static decimal.context.DecimalContext context32 = {
        precision : 7,
        rounding : Rounding.HALF_EVEN,
        eMax : E_MAX
    };

private:
    // The total number of bits in the decimal number.
    // This is equal to the number of bits in the underlying integer;
    // (must be 32, 64, or 128).
    immutable uint bitLength = 32;

    // the number of bits in the sign bit (1, obviously)
    immutable uint signBit = 1;

    // The number of bits in the unsigned value of the decimal number.
    immutable uint unsignedBits = 31; // = bitLength - signBit;

    // The number of bits in the (biased) exponent.
    immutable uint expoBits = 8;

    // The number of bits in the coefficient when the value is
    // explicitly represented.
    immutable uint explicitBits = 23;

    // The number of bits used to indicate special values and implicit
    // representation
    immutable uint testBits = 2;

    // The number of bits in the coefficient when the value is implicitly
    // represented. The three missing bits (the most significant bits)
    // are always '100'.
    immutable uint implicitBits = 21; // = explicitBits - testBits;

    // The number of special bits, including the two test bits.
    // These bits are used to denote infinities and NaNs.
    immutable uint specialBits = 4;

    // The number of bits that follow the special bits.
    // Their number is the number of bits in an special value
    // when the others (sign and special) are accounted for.
    immutable uint spclPadBits = 27;
            // = bitLength - infinityBits - signBit;

    // The number of infinity bits, including the special bits.
    // These bits are used to denote infinity.
    immutable uint infinityBits = 5;

    // The number of bits that follow the special bits in infinities.
    // These bits are always set to zero in canonical representations.
    // Their number is the remaining number of bits in an infinity
    // when all others (sign and infinity) are accounted for.
    immutable uint infPadBits = 26;
            // = bitLength - infinityBits - signBit;

    // The number of nan bits, including the special bits.
    // These bits are used to denote NaN.
    immutable uint nanBits = 6;

    // The number of bits in the payload of a NaN.
    immutable uint payloadBits = 16;

    // The number of bits that follow the nan bits in NaNs.
    // These bits are always set to zero in canonical representations.
    // Their number is the remaining number of bits in a NaN
    // when all others (sign, nan and payload) are accounted for.
    immutable uint nanPadBits = 9;
            // = bitLength - payloadBits - specialBits - signBit;

    // The exponent bias. The exponent is stored as an unsigned number and
    // the bias is subtracted from the unsigned value to give the true
    // (signed) exponent.
    immutable int BIAS = 101;   // = 0x65

    // The maximum biased exponent.
    // The largest binary number that can fit in the width of the
    // exponent without setting either of the first two bits to 1.
    immutable uint MAX_BSXP = 0xBF; // = 191

    // length of the coefficient in decimal digits.
    immutable int MANT_LENGTH = 7;
    // The maximum coefficient that fits in an explicit number.
    immutable uint MAX_XPLC = 0x7FFFFF; // = 8388607;
    // The maximum coefficient allowed in an implicit number.
    immutable uint MAX_IMPL = 9999999;  // = 0x98967F;
    // The maximum representable exponent.
    immutable int  MAX_EXPO  =   90;    // = MAX_BSXP - BIAS;
    // The minimum representable exponent.
    immutable int  MIN_EXPO  = -101;    // = 0 - BIAS.

    // The min and max adjusted exponents.
    immutable int E_MAX   = MAX_EXPO;
    immutable int E_MIN   = -E_MAX;

    // masks for coefficients
    immutable uint MASK_IMPL = 0x1FFFFF;
    immutable uint MASK_XPLC = 0x7FFFFF;

    // union providing different views of the number representation.
    union {

        // entire 32-bit unsigned integer
        uint intBits = SV.POS_NAN;    // set to the initial value: NaN

        // unsigned value and sign bit
        mixin (bitfields!(
            uint, "uBits", unsignedBits,
            bool, "signed", signBit)
        );
        // Ex = explicit finite number:
        //     full coefficient, exponent and sign
        mixin (bitfields!(
            uint, "mantEx", explicitBits,
            uint, "expoEx", expoBits,
            bool, "signEx", signBit)
        );
        // Im = implicit finite number:
        //      partial coefficient, exponent, test bits and sign bit.
        mixin (bitfields!(
            uint, "mantIm", implicitBits,
            uint, "expoIm", expoBits,
            uint, "testIm", testBits,
            bool, "signIm", signBit)
        );
        // Spcl = special values: non-finite numbers
        //      unused bits, special bits and sign bit.
        mixin (bitfields!(
            uint, "padSpcl",  spclPadBits,
            uint, "testSpcl", specialBits,
            bool, "signSpcl", signBit)
        );
        // Inf = infinities:
        //      payload, unused bits, infinitu bits and sign bit.
        mixin (bitfields!(
            uint, "padInf",  infPadBits,
            uint, "testInf", infinityBits,
            bool, "signInf", signBit)
        );
        // Nan = not-a-number: qNaN and sNan
        //      payload, unused bits, nan bits and sign bit.
        mixin (bitfields!(
            uint, "pyldNaN", payloadBits,
            uint, "padNaN",  nanPadBits,
            uint, "testNaN", nanBits,
            bool, "signNaN", signBit)
        );
    }

//--------------------------------
//  special values
//--------------------------------

private:
    // The value of the (6) special bits when the number is a signaling NaN.
    immutable uint SIG_VAL = 0x3F;
    // The value of the (6) special bits when the number is a quiet NaN.
    immutable uint NAN_VAL = 0x3E;
    // The value of the (5) special bits when the number is infinity.
    immutable uint INF_VAL = 0x1E;

    static enum SV : uint
    {
        // The value corresponding to a positive signaling NaN.
        POS_SIG = 0x7E000000,
        // The value corresponding to a negative signaling NaN.
        NEG_SIG = 0xFE000000,

        // The value corresponding to a positive quiet NaN.
        POS_NAN = 0x7C000000,
        // The value corresponding to a negative quiet NaN.
        NEG_NAN = 0xFC000000,

        // The value corresponding to positive infinity.
        POS_INF = 0x78000000,
        // The value corresponding to negative infinity.
        NEG_INF = 0xF8000000,

        // The value corresponding to positive zero. (+0)
        POS_ZRO = 0x32800000,
        // The value corresponding to negative zero. (-0)
        NEG_ZRO = 0xB2800000,

        // The value of the largest representable positive number.
        POS_MAX = 0x77F8967F,
        // The value of the largest representable negative number.
        NEG_MAX = 0xF7F8967F
    }

public:
    immutable Dec32 NAN      = Dec32(SV.POS_NAN);
    immutable Dec32 NEG_NAN  = Dec32(SV.NEG_NAN);
    immutable Dec32 SNAN     = Dec32(SV.POS_SIG);
    immutable Dec32 NEG_SNAN = Dec32(SV.NEG_SIG);
    immutable Dec32 INFINITY = Dec32(SV.POS_INF);
    immutable Dec32 NEG_INF  = Dec32(SV.NEG_INF);
    immutable Dec32 ZERO     = Dec32(SV.POS_ZRO);
    immutable Dec32 NEG_ZERO = Dec32(SV.NEG_ZRO);
    immutable Dec32 MAX      = Dec32(SV.POS_MAX);
    immutable Dec32 NEG_MAX  = Dec32(SV.NEG_MAX);

//--------------------------------
//  constructors
//--------------------------------

    /**
     * Creates a Dec32 from a special value.
     */
    private this(const SV sv) {
        intBits = sv;
    }

    // this unit test uses private values
    unittest {
        Dec32 num;
        num = Dec32(SV.POS_SIG);
        assert(num.isSignaling);
        assert(num.isNaN);
        assert(!num.isNegative);
        assert(!num.isNormal);
        num = Dec32(SV.NEG_SIG);
        assert(num.isSignaling);
        assert(num.isNaN);
        assert(num.isNegative);
        assert(!num.isNormal);
        num = Dec32(SV.POS_NAN);
        assert(!num.isSignaling);
        assert(num.isNaN);
        assert(!num.isNegative);
        assert(!num.isNormal);
        num = Dec32(SV.NEG_NAN);
        assert(!num.isSignaling);
        assert(num.isNaN);
        assert(num.isNegative);
        assert(num.isQuiet);
        num = Dec32(SV.POS_INF);
        assert(num.isInfinite);
        assert(!num.isNaN);
        assert(!num.isNegative);
        assert(!num.isNormal);
        num = Dec32(SV.NEG_INF);
        assert(!num.isSignaling);
        assert(num.isInfinite);
        assert(num.isNegative);
        assert(!num.isFinite);
        num = Dec32(SV.POS_ZRO);
        assert(num.isFinite);
        assert(num.isZero);
        assert(!num.isNegative);
        assert(num.isNormal);
        num = Dec32(SV.NEG_ZRO);
        assert(!num.isSignaling);
        assert(num.isZero);
        assert(num.isNegative);
        assert(num.isFinite);
    }

    /**
     * Creates a Dec32 from a long integer.
     */
    public this(const long n)
    {
        this = zero;
        signed = n < 0;
        coefficient = std.math.abs(n);
    }

    unittest {
        Dec32 num;
        num = Dec32(1234567890L);
        assert(num.toString == "1.234568E+9");
        num = Dec32(0);
        assert(num.toString == "0");
        num = Dec32(1);
        assert(num.toString == "1");
        num = Dec32(-1);
        assert(num.toString == "-1");
        num = Dec32(5);
        assert(num.toString == "5");
    }

    /**
     * Creates a Dec32 from an unsigned integer and integer exponent.
     */
    public this(const long mant, const int expo) {
        this(mant);
        exponent = exponent + expo;
    }

    unittest {
        Dec32 num;
        num = Dec32(1234567890L, 5);
        assert(num.toString == "1.234568E+14");
        num = Dec32(0, 2);
        assert(num.toString == "0E+2");
        num = Dec32(1, 75);
        assert(num.toString == "1E+75");
        num = Dec32(-1, -75);
        assert(num.toString == "-1E-75");
        num = Dec32(5, -3);
        assert(num.toString == "0.005");
    }

    /**
     * Creates a Dec32 from a Decimal
     */
    public this(const Decimal num) {

        Decimal big = plus!Decimal(num, context32);

        if (big.isFinite) {
            this = zero;
            this.coefficient = cast(ulong)big.coefficient.toLong;
            this.exponent = big.exponent;
            this.sign = big.sign;
            return;
        }
        // check for special values
        else if (big.isInfinite) {
            this = infinity(big.sign);
            return;
        }
        else if (big.isQuiet) {
            this = nan(big.sign);
            return;
        }
        else if (big.isSignaling) {
            this = snan(big.sign);
            return;
        }

    }

   unittest {
        Decimal dec = 0;
        Dec32 num = dec;
        assert(dec.toString == num.toString);
        dec = 1;
        num = dec;
        assert(dec.toString == num.toString);
        dec = -1;
        num = dec;
        assert(dec.toString == num.toString);
        dec = -16000;
        num = dec;
        assert(dec.toString == num.toString);
        dec = uint.max;
        num = dec;
        assert(num.toString == "4.294967E+9");
        assert(dec.toString == "4294967295");
        dec = 9999999E+12;
        num = dec;
        assert(dec.toString == num.toString);
    }

    /**
     * Creates a Dec32 from a string.
     */
    public this(const string str) {
        Decimal big = Decimal(str);
        this(big);
    }

    unittest {
        Dec32 num;
        num = Dec32("1.234568E+9");
        assert(num.toString == "1.234568E+9");
        num = Dec32("NaN");
        assert(num.isQuiet && num.isSpecial && num.isNaN);
        num = Dec32("-inf");
        assert(num.isInfinite && num.isSpecial && num.isNegative);
    }

    /**
     *    Constructs a number from a real value.
     */
    public this(const real r) {
        // check for special values
        if (!std.math.isFinite(r)) {
            this = std.math.isInfinity(r) ? INFINITY : NAN;
            this.sign = cast(bool)std.math.signbit(r);
            return;
        }
        string str = format("%.*G", cast(int)context32.precision, r);
        this(str);
    }

    unittest {
        float f = 1.2345E+16f;
        Dec32 actual = Dec32(f);
        Dec32 expect = Dec32("1.2345E+16");
        assert(expect == actual);
        real r = 1.2345E+16;
        actual = Dec32(r);
        expect = Dec32("1.2345E+16");
        assert(expect == actual);
    }

    /**
     * Copy constructor.
     */
    public this(const Dec32 that) {
        this.bits = that.bits;
    }

    /**
     * duplicator.
     */
    const Dec32 dup() {
        return Dec32(this);
    }

//--------------------------------
//  properties
//--------------------------------

public:

    /// Returns the raw bits of this number.
    @property
    const uint bits() {
        return intBits;
    }

    /// Sets the raw bits of this number.
    @property
    uint bits(const uint raw) {
        intBits = raw;
        return intBits;
    }

    /// Returns the sign of this number.
    @property
    const bool sign() {
        return signed;
    }

    /// Sets the sign of this number and returns the sign.
    @property
    bool sign(const bool value) {
        signed = value;
        return signed;
    }

    /// Returns the exponent of this number.
    /// The exponent is undefined for infinities and NaNs: zero is returned.
    @property
    const int exponent() {
        if (this.isExplicit) {
            return expoEx - BIAS;
        }
        if (this.isImplicit) {
            return expoIm - BIAS;
        }
        // infinity or NaN.
        return 0;
    }

    unittest {
        Dec32 num;
        // reals
        num = std.math.PI;
        assert(num.exponent = -6);
        num = 9.75E89;
        assert(num.exponent = 87);
        // explicit
        num = 8388607;
        assert(num.exponent = 0);
        // implicit
        num = 8388610;
        assert(num.exponent = 0);
        num = 9.999998E23;
        assert(num.exponent = 17);
        num = 9.999999E23;
        assert(num.exponent = 17);
    }

    /// Sets the exponent of this number.
    /// If this number is infinity or NaN, this number is converted to
    /// a quiet NaN and the invalid operation flag is set.
    /// Otherwise, if the input value exceeds the maximum allowed exponent,
    /// this number is converted to infinity and the overflow flag is set.
    /// If the input value is less than the minimum allowed exponent,
    /// this number is converted to zero, the exponent is set to eTiny
    /// and the underflow flag is set.
    @property
     int exponent(const int expo) {
        // check for overflow
        if (expo > context32.eMax) {
            this = signed ? NEG_INF : INFINITY;
            context32.setFlag(OVERFLOW);
            return 0;
        }
        // check for underflow
        if (expo < context32.eMin) {
            // if the exponent is too small even for a subnormal number,
            // the number is set to zero.
            if (expo < context32.eTiny) {
                this = signed ? NEG_ZERO : ZERO;
                expoEx = context32.eTiny + BIAS;
                context32.setFlag(SUBNORMAL);
                context32.setFlag(UNDERFLOW);
                return context32.eTiny;
            }
            // at this point the exponent is between eMin and eTiny.
            // NOTE: I don't think this needs special handling
        }
        // if explicit...
        if (this.isExplicit) {
            expoEx = expo + BIAS;
            return expoEx;
        }
        // if implicit...
        if (this.isFinite) {
            expoIm = expo + BIAS;
            return expoIm;
        }
        // if this point is reached the number is either infinity or NaN;
        // these have undefined exponent values.
        context32.setFlag(INVALID_OPERATION);
        this = nan;
        return 0;
    }

    unittest {
        Dec32 num;
        num = Dec32(-12000,5);
        num.exponent = 10;
        assert(num.exponent == 10);
        num = Dec32(-9000053,-14);
        num.exponent = -27;
        assert(num.exponent == -27);
        num = infinity;
        assert(num.exponent == 0);
    }

    /// Returns the coefficient of this number.
    /// The exponent is undefined for infinities and NaNs: zero is returned.
    @property
    const uint coefficient() {
        if (this.isExplicit) {
            return mantEx;
        }
        if (this.isFinite) {
            return mantIm | (0b100 << implicitBits);
        }
        // Infinity or NaN.
        return 0;
    }

    // Sets the coefficient of this number. This may cause an
    // explicit number to become an implicit number, and vice versa.
    @property
    uint coefficient(const ulong mant) {
        // if not finite, convert to NaN and return 0.
        if (!this.isFinite) {
            this = nan;
            context32.setFlag(INVALID_OPERATION);
            return 0;
        }
        ulong copy = mant;
        if (copy > MAX_IMPL) {
            int expo = 0;
            uint digits = numDigits(copy);
            expo = setExponent(sign, copy, digits, context32);
            if (this.isExplicit) {
                expoEx = expoEx + expo;
            }
            else {
                expoIm = expoIm + expo;
            }
        }
        // at this point, the number <= MAX_IMPL
        if (copy <= MAX_XPLC) {
            // if implicit, convert to explicit
            if (this.isImplicit) {
                expoEx = expoIm;
            }
            mantEx = cast(uint)copy;
            return mantEx;
        }
        else {  // copy <= MAX_IMPL
            // if explicit, convert to implicit
            if (this.isExplicit) {
                expoIm = expoEx;
                testIm = 0x3;
            }
            mantIm = cast(uint)copy & MASK_IMPL;
            return mantIm | (0b100 << implicitBits);
        }
    }

    unittest {
        Dec32 num;
        assert(num.coefficient == 0);
        num = 9.998743;
        assert(num.coefficient == 9998743);
        num = Dec32(9999213,-6);
        assert(num.coefficient == 9999213);
        num = -125;
        assert(num.coefficient == 125);
        num = -99999999;
        assert(num.coefficient == 1000000);
    }

    /// Returns the number of digits in this number's coefficient.
    @property
    const int digits() {
        return numDigits(this.coefficient);
    }

    // (3) TODO: digits
    // I think this should ensure the coefficient has only the specified
    // number of digits and adjust the exponent as needed.
    @property
    const int digits(const int digs) {
        return digs;
    }

    /// Returns the payload of this number.
    /// If this is a NaN, returns the value of the payload bits.
    /// Otherwise returns zero.
    @property
    const uint payload() {
        if (this.isNaN) {
            return pyldNaN;
        }
        return 0;
    }

    /// Sets the payload of this number.
    /// If the number is not a NaN (har!) no action is taken and zero
    /// is returned.
    @property
    uint payload(const uint value) {
        if (isNaN) {
            pyldNaN = value;
            return pyldNaN;
        }
        return 0;
    }

    unittest {
        Dec32 num;
        assert(num.payload == 0);
        num = snan;
        assert(num.payload == 0);
        num.payload = 234;
        assert(num.payload == 234);
        assert(num.toString == "sNaN234");
        num = 1234567;
        assert(num.payload == 0);
    }

//--------------------------------
//  constants
//--------------------------------

    static Dec32 zero(const bool signed = false) {
        return signed ? NEG_ZERO : ZERO;
    }

    static Dec32 infinity(const bool signed = false) {
        return signed ? NEG_INF : INFINITY;
    }

    static Dec32 nan(const bool signed = false) {
        return signed ? NEG_NAN : NAN;
    }

    static Dec32 snan(const bool signed = false) {
        return signed ? NEG_SNAN : SNAN;
    }

    static Dec32 max(const bool signed = false) {
        return signed ? NEG_MAX : MAX;
    }

    // floating point properties
    static Dec32 init()       { return NAN; }
    static Dec32 nan()        { return NAN; }
    static Dec32 snan()       { return SNAN; }

    static Dec32 epsilon()    { return Dec32(1, -7); }
    static Dec32 max()        { return MAX; }
    static Dec32 min_normal() { return Dec32(1, context32.eMin); }
    static Dec32 min()        { return Dec32(1, context32.eTiny); }

    static int dig()        { return 7; }
    static int mant_dig()   { return 24; }
    static int max_10_exp() { return context32.eMax; }
    static int min_10_exp() { return context32.eMin; }
    static int max_exp()    { return cast(int)(context32.eMax/LOG2); }
    static int min_exp()    { return cast(int)(context32.eMin/LOG2); }

    /// Returns the maximum number of decimal digits in this context.
    static uint precision(DecimalContext context = context32) {
        return context.precision;
    }

    /// Returns the maximum number of decimal digits in this context.
    static uint dig(DecimalContext context = context32) {
        return context.precision;
    }

    /// Returns the number of binary digits in this context.
    static uint mant_dig(DecimalContext context = context32) {
        return cast(int)context.mant_dig;
    }

    static int min_exp(DecimalContext context = context32) {
        return context.min_exp;
    }

    static int max_exp(DecimalContext context = context32) {
        return context.max_exp;
    }

    /// Returns the minimum representable normal value in this context.
    static Dec32 min_normal(DecimalContext context = context32) {
        return Dec32(1, context.eMin);
    }

    /// Returns the minimum representable subnormal value in this context.
    // (5) TODO: does this set the subnormal flag?
    // Do others do the same on creation??
    static Dec32 min(DecimalContext context = context32) {
        return Dec32(1, context.eTiny);
    }

    /// returns the smallest available increment to 1.0 in this context
    static Dec32 epsilon(DecimalContext context = context32) {
        return Dec32(1, -context.precision);
    }

    static int min_10_exp(DecimalContext context = context32) {
        return context.eMin;
    }

    static int max_10_exp(DecimalContext context = context32) {
        return context.eMax;
    }

//--------------------------------
//  classification properties
//--------------------------------

    /**
     * Returns true if this number's representation is canonical.
     * Finite numbers are always canonical.
     * Infinities and NaNs are canonical if their unused bits are zero.
     */
    const bool isCanonical() {
        if (isFinite)   return true;
        if (isInfinite) return this.padInf == 0;
        /* isNaN */     return this.padNaN == 0;
    }

    /**
     * Returns true if this number's representation is canonical.
     * Finite numbers are always canonical.
     * Infinities and NaNs are canonical if their unused bits are zero.
     */
    const Dec32 canonical() {
        Dec32 copy = this;
        if (this.isCanonical) return copy;
        if (this.isInfinite) {
            copy.padInf = 0;
            return copy;
        }
        else { /* isNaN */
            copy.padNaN = 0;
            return copy;
        }
    }

    /**
     * Returns true if this number is +\- zero.
     */
    const bool isZero() {
        return isExplicit && mantEx == 0;
    }

    /**
     * Returns true if this number is a quiet or signaling NaN.
     */
    const bool isNaN() {
        return testNaN == NAN_VAL || testNaN == SIG_VAL;
    }

    /**
     * Returns true if this number is a signaling NaN.
     */
    const bool isSignaling() {
        return testNaN == SIG_VAL;
    }

    /**
     * Returns true if this number is a quiet NaN.
     */
    const bool isQuiet() {
        return testNaN == NAN_VAL;
    }

    /**
     * Returns true if this number is +\- infinity.
     */
    const bool isInfinite() {
        return testInf == INF_VAL;
    }

    /**
     * Returns true if this number is neither infinite nor a NaN.
     */
    const bool isFinite() {
        return testSpcl != 0xF;
    }

    /**
     * Returns true if this number is a NaN or infinity.
     */
    const bool isSpecial() {
        return testSpcl == 0xF;
    }

    const bool isExplicit() {
        return testIm != 0x3;
    }

    const bool isImplicit() {
        return testIm == 0x3 && testSpcl != 0xF;
    }

    /**
     * Returns true if this number is negative. (Includes -0)
     */
    const bool isSigned() {
        return signed;
    }

    const bool isNegative() {
        return signed;
    }

    /**
     * Returns true if this number is subnormal.
     */
    const bool isSubnormal() {
        if (isSpecial) return false;
        return adjustedExponent < MIN_EXPO;
    }

    /**
     * Returns true if this number is normal.
     */
    const bool isNormal() {
        if (isSpecial) return false;
        return adjustedExponent >= MIN_EXPO;
    }

    /**
     * Returns the value of the adjusted exponent.
     */
     const int adjustedExponent() {
        return exponent + digits - 1;
     }

//--------------------------------
//  conversions
//--------------------------------

    /**
     * Converts a Dec32 to a Decimal
     */
    const Decimal toDecimal() {
        if (isFinite) {
            return Decimal(sign, BigInt(coefficient), exponent);
        }
        if (isInfinite) {
            return Decimal.infinity(sign);
        }
        // number is a NaN
        Decimal dec;
        if (isQuiet) {
            dec = Decimal.nan(sign);
        }
        if (isSignaling) {
            dec = Decimal.snan(sign);
        }
        if (payload) {
            dec.payload(payload);
        }
        return dec;
    }

    unittest {
        write("toDecimal...");
        writeln("test missing");
    }

    /**
     * Converts this number to an exact scientific-style string representation.
     */
    const string toSciString() {
        return decimal.conv.toSciString!Dec32(this);
    }

    /**
     * Converts this number to an exact engineering-style string representation.
     */
    const string toEngString() {
        return decimal.conv.toEngString!Dec32(this);
    }

    /**
     * Converts a Dec32 to a string
     */
    const public string toString() {
         return toSciString();
    }

    unittest {
        write("toString...");
        writeln("test missing");
    }

    /**
     * Creates an exact representation of this number.
     */
    const string toExact()
    {
        if (this.isFinite) {
            return format("%s%07dE%s%02d", signed ? "-" : "+", coefficient,
                    exponent < 0 ? "-" : "+", exponent);
        }
        if (this.isInfinite) {
            return format("%s%s", signed ? "-" : "+", "Infinity");
        }
        if (this.isQuiet) {
            if (payload) {
                return format("%s%s%d", signed ? "-" : "+", "NaN", payload);
            }
            return format("%s%s", signed ? "-" : "+", "NaN");
        }
        // this.isSignaling
        if (payload) {
            return format("%s%s%d", signed ? "-" : "+", "sNaN", payload);
        }
        return format("%s%s", signed ? "-" : "+", "sNaN");
    }

    unittest {
        write("toExact...");
        Dec32 num;
        assert(num.toExact == "+NaN");
        num = max;
        assert(num.toExact == "+9999999E+90");
        num = 1;
        assert(num.toExact == "+0000001E+00");
        num = MAX_XPLC;
        assert(num.toExact == "+8388607E+00");
        num = infinity(true);
        assert(num.toExact == "-Infinity");
        writeln("passed");
    }

    /**
     * Creates an abstract representation of this number.
     */
    const string toAbstract()
    {
        if (this.isFinite) {
            return format("[%d,%s,%d]", signed ? 1 : 0, coefficient, exponent);
        }
        if (this.isInfinite) {
            return format("[%d,%s]", signed ? 1 : 0, "inf");
        }
        if (this.isQuiet) {
            if (payload) {
                return format("[%d,%s,%d]", signed ? 1 : 0, "qNaN", payload);
            }
            return format("[%d,%s]", signed ? 1 : 0, "qNaN");
        }
        // this.isSignaling
        if (payload) {
            return format("[%d,%s,%d]", signed ? 1 : 0, "sNaN", payload);
        }
        return format("[%d,%s]", signed ? 1 : 0, "sNaN");
    }

    unittest {
        write("toAbstract...");
        writeln("test missing");
    }

    /**
     * Converts this number to a hexadecimal string representation.
     */
    public string toHexString() {
         return format("0x%08X", bits);
    }

    /**
     * Converts this number to a binary string representation.
     */
    const string toBinaryString() {
        return format("%0#32b", bits);
    }

    unittest {
        Dec32 num = 12345;
        assert(num.toHexString == "0x32803039");
        assert(num.toBinaryString == "00110010100000000011000000111001");
    }

//--------------------------------
//  comparison
//--------------------------------

    /**
     * Returns -1, 0 or 1, if this number is less than, equal to or
     * greater than the argument, respectively.
     */
    const int opCmp(const Dec32 that) {
        return compare!Dec32(this, that, context32);
    }

    unittest {
        Dec32 a, b;
        a = Dec32(104.0);
        b = Dec32(105.0);
        assert(a < b);
        assert(b > a);
    }

    /**
     * Returns true if this number is equal to the specified number.
     */
    const bool opEquals(ref const Dec32 that) {
        // quick bitwise check
        if (this.bits == that.bits) {
            if (this.isFinite) return true;
            if (this.isInfinite) return true;
            if (this.isQuiet) return false;
            // let the main routine handle the signaling NaN
        }
        return equals!Dec32(this, that, context32);
    }

    unittest {
        Dec32 a, b;
        a = Dec32(105);
        b = Dec32(105);
        assert(a == b);
    }

//--------------------------------
// assignment
//--------------------------------

    // (7) UNREADY: opAssign(T: Dec32)(const Dec32). Flags. Unit Tests.
    /// Assigns a Dec32 (copies that to this).
    void opAssign(T:Dec32)(const T that) {
        this.intBits = that.intBits;
    }

    unittest {
        Dec32 rhs, lhs;
        rhs = Dec32(270E-5);
        lhs = rhs;
        assert(lhs == rhs);
    }

    // (7) UNREADY: opAssign(T)(const T). Flags.
    ///    Assigns a numeric value.
    void opAssign(T)(const T that) {
        this = Dec32(that);
    }

    unittest {
        Dec32 rhs;
        rhs = 332089;
        assert(rhs.toString == "332089");
        rhs = 3.1415E+3;
        assert(rhs.toString == "3141.5");
    }

//--------------------------------
// unary operators
//--------------------------------

    const Dec32 opUnary(string op)()
    {
        static if (op == "+") {
            return plus!Dec32(this, context32);
        }
        else static if (op == "-") {
            return minus!Dec32(this, context32);
        }
        else static if (op == "++") {
            return add!Dec32(this, Dec32(1), context32);
        }
        else static if (op == "--") {
            return subtract!Dec32(this, Dec32(1), context32);
        }
    }

    unittest {
        Dec32 num, actual, expect;
        num = 134;
        expect = num;
        actual = +num;
        assert(actual == expect);
        num = 134.02;
        expect = -134.02;
        actual = -num;
        assert(actual == expect);
        num = 134;
        expect = 135;
        actual = ++num;
        assert(actual == expect);
        // (4) TODO: seems to be broken for nums like 1.000E8
        // they should be unchanged since the bump is too small.
        num = 1.00E8;
        expect = num;
        actual = --num;
writeln("expect = ", expect);
writeln("actual = ", actual);
        num = 9999999E70; //Dec32("9999999E90");
        num = Dec32(9999999, 90);
writeln("num = ", num);
writeln("num.toHexString = ", num.toHexString);
writeln("num.toAbstract = ", num.toAbstract);
writeln("num.toBinaryString = ", num.toBinaryString);
        num = 12.35;
        expect = 11.35;
        actual = --num;
        assert(actual == expect);
    }

//--------------------------------
// binary operators
//--------------------------------

    const Dec32 opBinary(string op)(const Dec32 rhs)
    {
        static if (op == "+") {
            return add!Dec32(this, rhs, context32);
        }
        else static if (op == "-") {
            return subtract!Dec32(this, rhs, context32);
        }
        else static if (op == "*") {
            return multiply!Dec32(this, rhs, context32);
        }
        else static if (op == "/") {
            return divide!Dec32(this, rhs, context32);
        }
        else static if (op == "%") {
            return remainder!Dec32(this, rhs, context32);
        }
    }

    unittest {
        Dec32 op1, op2, actual, expect;
        op1 = 4;
        op2 = 8;
        actual = op1 + op2;
        expect = 12;
        assert(expect == actual);
        actual = op1 - op2;
        expect = -4;
        assert(expect == actual);
        actual = op1 * op2;
        expect = 32;
        assert(expect == actual);
        op1 = 5;
        op2 = 2;
        actual = op1 / op2;
        expect = 2.5;
        assert(expect == actual);
        op1 = 10;
        op2 = 3;
        actual = op1 % op2;
        expect = 1;
        assert(expect == actual);
    }

//-----------------------------
// operator assignment
//-----------------------------

    ref Dec32 opOpAssign(string op) (Dec32 rhs) {
        this = opBinary!op(rhs);
        return this;
    }

    unittest {
        Dec32 op1, op2, actual, expect;
        op1 = 23.56;
        op2 = -2.07;
        op1 += op2;
        expect = 21.49;
        actual = op1;
        assert(expect == actual);
        op1 *= op2;
        expect = -44.4843;
        actual = op1;
        assert(expect == actual);
    }


//-----------------------------
// helper functions
//-----------------------------

     /**
     * Returns uint ten raised to the specified power.
     */
    static uint pow10(const int n) {
        return 10U^^n;
    }

    unittest {
        assert(pow10(3) == 1000);
    }

}   // end Dec32 struct

// (7) TODO: when all are copied, delete this.
unittest {
    writeln("---------------------");
    writeln("decimal32....finished");
    writeln("---------------------");
}


