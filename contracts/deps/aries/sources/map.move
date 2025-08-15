module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::map {

    use 0x1::option;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::iterable_table;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::map;

    struct Element<T0, T1> has copy, drop, store {
        key: T0,
        value: T1,
    }
    struct Map<T0, T1> has copy, drop, store {
        data: vector<map::Element<T0, T1>>,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun add<T0: copy+ drop, T1>(a0: &mut map::Map<T0, T1>, a1: T0, a2: T1);
    #[native_interface]
    native public fun borrow<T0: copy+ drop, T1>(a0: &map::Map<T0, T1>, a1: T0): &T1;
    #[native_interface]
    native public fun borrow_inner<T0: copy+ drop, T1>(a0: &map::Map<T0, T1>, a1: T0): (&T1, u64);
    #[native_interface]
    native public fun borrow_iter<T0: copy+ drop, T1>(a0: &map::Map<T0, T1>, a1: T0): (&T1, option::Option<T0>, option::Option<T0>);
    #[native_interface]
    native public fun borrow_iter_mut<T0: copy+ drop, T1>(a0: &mut map::Map<T0, T1>, a1: T0): (&mut T1, option::Option<T0>, option::Option<T0>);
    #[native_interface]
    native public fun borrow_mut<T0: copy+ drop, T1>(a0: &mut map::Map<T0, T1>, a1: T0): &mut T1;
    #[native_interface]
    native public fun borrow_mut_with_default<T0: copy+ drop, T1: drop>(a0: &mut map::Map<T0, T1>, a1: T0, a2: T1): &mut T1;
    #[native_interface]
    native public fun contains<T0: copy+ drop, T1>(a0: &map::Map<T0, T1>, a1: T0): bool;
    #[native_interface]
    native public fun destroy_empty<T0: copy+ drop, T1>(a0: map::Map<T0, T1>);
    #[native_interface]
    native public fun empty<T0: copy+ drop, T1>(a0: &map::Map<T0, T1>): bool;
    #[native_interface]
    native public fun from_iterable_table<T0: copy+ drop+ store, T1: copy+ store>(a0: &iterable_table::IterableTable<T0, T1>): map::Map<T0, T1>;
    #[native_interface]
    native public fun get<T0: copy+ drop, T1: copy>(a0: &map::Map<T0, T1>, a1: T0): T1;
    #[native_interface]
    native public fun head_key<T0: copy+ drop, T1>(a0: &map::Map<T0, T1>): option::Option<T0>;
    #[native_interface]
    native public fun keys<T0: copy, T1>(a0: &map::Map<T0, T1>): vector<T0>;
    #[native_interface]
    native public fun length<T0: copy+ drop, T1>(a0: &map::Map<T0, T1>): u64;
    #[native_interface]
    native public fun new<T0: copy+ drop, T1>(): map::Map<T0, T1>;
    #[native_interface]
    native public fun remove<T0: copy+ drop, T1>(a0: &mut map::Map<T0, T1>, a1: T0): (T0, T1);
    #[native_interface]
    native public fun tail_key<T0: copy+ drop, T1>(a0: &map::Map<T0, T1>): option::Option<T0>;
    #[native_interface]
    native public fun to_vec_pair<T0: store, T1: store>(a0: map::Map<T0, T1>): (vector<T0>, vector<T1>);
    #[native_interface]
    native public fun upsert<T0: copy+ drop, T1>(a0: &mut map::Map<T0, T1>, a1: T0, a2: T1): (option::Option<T0>, option::Option<T1>);
    #[native_interface]
    native public fun values<T0, T1: copy>(a0: &map::Map<T0, T1>): vector<T1>;

}
