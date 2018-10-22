/*
    D advanced binding for Duktape.

    It add automatic registration of D objects.
*/
import std.stdio;
import etc.c.duktape;


/** Advanced duk context. */
final class DukContext
{
    import std.traits;
    import std.conv : to;
    import std.string : toStringz, fromStringz;

private:
    duk_context *_ctx;
public:
    this()
    {
        _ctx = duk_create_heap_default;
    }

    ~this()
    {
        duk_destroy_heap(_ctx);
    }

    void evalString(string js)
    {
        duk_eval_string(_ctx, js.toStringz());
    }

    /// Automatic registration of D function.
    void register(alias Func)(string name = __traits(identifier, Func)) if (isFunction!Func)
    {
        auto externFunc = generateExternDukFunc!Func;
        duk_push_c_function(_ctx, externFunc, Parameters!Func.length /*nargs*/);
        duk_put_global_string(_ctx, name.toStringz());
    }

    /// Automatic registration of D enum.
    void register(alias Enum)(string name = __traits(identifier, Enum)) if (is(Enum == enum))
    {
        alias EnumBaseType = OriginalType!Enum;

        duk_idx_t arr_idx;
        arr_idx = duk_push_array(_ctx);

        // push a js array
        static foreach(Member; [EnumMembers!Enum]) {
            this.push!EnumBaseType(_ctx, cast(EnumBaseType) Member); // push value
            duk_put_prop_string(_ctx, arr_idx, to!string(Member).toStringz()); // push string prop
        }
        duk_put_global_string(_ctx, name.toStringz()); // push enum name
    }

    T get(T)(int idx = -1)
    {
        return get!T(_ctx, idx);
    }

    /// Utility method to get a type on the stack.
    private static T get(T)(duk_context *ctx, int idx)
    {
        static if (is(T == int))    return duk_get_int(ctx, idx);
        static if (is(T == bool))   return duk_get_boolean(ctx, idx);
        static if (is(T == float))  return duk_get_number(ctx, idx);
        static if (is(T == double)) return duk_get_number(ctx, idx);
        static if (is(T == string)) return fromStringz(duk_get_string(ctx, idx)).to!string;
    }

    /// Utility method to push a type on the stack.
    private static void push(T)(duk_context *ctx, T value)
    {
        static if (is(T == int))    duk_push_int(ctx, value);
        static if (is(T == bool))   duk_push_boolean(ctx, value);
        static if (is(T == float))  duk_push_number(ctx, value);
        static if (is(T == double)) duk_push_number(ctx, value);
        static if (is(T == string)) duk_push_string(ctx, value.toStringz());
    }

    auto generateExternDukFunc(alias Func)() if (isFunction!Func)
    {
        import std.typecons;

        extern(C) static duk_ret_t func(duk_context *ctx) {
            int n = duk_get_top(ctx);  // number of args

            // check parameter count
            if (n != Parameters!Func.length)
                return DUK_RET_RANGE_ERROR;

            // create a tuple of arguments
            Tuple!(Parameters!Func) args;
            static foreach(i, ArgType; Parameters!Func) {
                args[i] = get!ArgType(ctx, i);
            }

            // call the function
            if (is(ReturnType!Func == void)) {
                // TODO: handle void
            }
            else {
                ReturnType!Func ret = Func(args.expand);
                push(ctx, ret);
            }

            return 1; // one return value
        }

        return &func;
    }
}

///
unittest
{
    static int add(int a, int b) {
        return a + b;
    }

    auto ctx = new DukContext();
    ctx.register!add;

    ctx.evalString("add(1, 5)");
    assert(ctx.get!int(-1) == 6);
}

///
unittest
{
    static string capitalize(string s) {
        import std.string : capitalize;
        return s.capitalize();
    }

    auto ctx = new DukContext();
    ctx.register!capitalize;

    ctx.evalString(`capitalize("hEllO")`);
    assert(ctx.get!string(-1) == "Hello");
}

/// register!Enum
unittest
{
    enum Direction
    {
        up,
        down
    }

    auto ctx = new DukContext();
    ctx.register!Direction;

    ctx.evalString("Direction['up']");
    assert(ctx.get!int() == 0);

    ctx.evalString("Direction['down']");
    assert(ctx.get!int() == 1);
}
