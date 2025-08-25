module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::pair {

    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::pair;

    struct Pair<T0, T1> has copy, drop, store {
        fst: T0,
        snd: T1,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun fst<T0, T1>(a0: &pair::Pair<T0, T1>): &T0;
    #[native_interface]
    native public fun new<T0, T1>(a0: T0, a1: T1): pair::Pair<T0, T1>;
    #[native_interface]
    native public fun prepend<T0, T1, T2>(a0: T0, a1: pair::Pair<T1, T2>): pair::Pair<T0, pair::Pair<T1, T2>>;
    #[native_interface]
    native public fun snd<T0, T1>(a0: &pair::Pair<T0, T1>): &T1;
    #[native_interface]
    native public fun split<T0, T1>(a0: pair::Pair<T0, T1>): (T0, T1);

}
