module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::iterable_table {

    use 0x1::option;
    use 0x1::table_with_length;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::iterable_table;

    struct IterableTable<T0: copy+ drop+ store, T1: store> has store {
        inner: table_with_length::TableWithLength<T0, iterable_table::IterableValue<T0, T1>>,
        head: option::Option<T0>,
        tail: option::Option<T0>,
    }
    struct IterableValue<T0: copy+ drop+ store, T1: store> has store {
        val: T1,
        prev: option::Option<T0>,
        next: option::Option<T0>,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun add<T0: copy+ drop+ store, T1: store>(a0: &mut iterable_table::IterableTable<T0, T1>, a1: T0, a2: T1);
    #[native_interface]
    native public fun append<T0: copy+ drop+ store, T1: store>(a0: &mut iterable_table::IterableTable<T0, T1>, a1: &mut iterable_table::IterableTable<T0, T1>);
    #[native_interface]
    native public fun borrow<T0: copy+ drop+ store, T1: store>(a0: &iterable_table::IterableTable<T0, T1>, a1: T0): &T1;
    #[native_interface]
    native public fun borrow_iter<T0: copy+ drop+ store, T1: store>(a0: &iterable_table::IterableTable<T0, T1>, a1: T0): (&T1, option::Option<T0>, option::Option<T0>);
    #[native_interface]
    native public fun borrow_iter_mut<T0: copy+ drop+ store, T1: store>(a0: &mut iterable_table::IterableTable<T0, T1>, a1: T0): (&mut T1, option::Option<T0>, option::Option<T0>);
    #[native_interface]
    native public fun borrow_mut<T0: copy+ drop+ store, T1: store>(a0: &mut iterable_table::IterableTable<T0, T1>, a1: T0): &mut T1;
    #[native_interface]
    native public fun borrow_mut_with_default<T0: copy+ drop+ store, T1: drop+ store>(a0: &mut iterable_table::IterableTable<T0, T1>, a1: T0, a2: T1): &mut T1;
    #[native_interface]
    native public fun contains<T0: copy+ drop+ store, T1: store>(a0: &iterable_table::IterableTable<T0, T1>, a1: T0): bool;
    #[native_interface]
    native public fun destroy_empty<T0: copy+ drop+ store, T1: store>(a0: iterable_table::IterableTable<T0, T1>);
    #[native_interface]
    native public fun empty<T0: copy+ drop+ store, T1: store>(a0: &iterable_table::IterableTable<T0, T1>): bool;
    #[native_interface]
    native public fun head_key<T0: copy+ drop+ store, T1: store>(a0: &iterable_table::IterableTable<T0, T1>): option::Option<T0>;
    #[native_interface]
    native public fun length<T0: copy+ drop+ store, T1: store>(a0: &iterable_table::IterableTable<T0, T1>): u64;
    #[native_interface]
    native public fun new<T0: copy+ drop+ store, T1: store>(): iterable_table::IterableTable<T0, T1>;
    #[native_interface]
    native public fun remove<T0: copy+ drop+ store, T1: store>(a0: &mut iterable_table::IterableTable<T0, T1>, a1: T0): T1;
    #[native_interface]
    native public fun remove_iter<T0: copy+ drop+ store, T1: store>(a0: &mut iterable_table::IterableTable<T0, T1>, a1: T0): (T1, option::Option<T0>, option::Option<T0>);
    #[native_interface]
    native public fun tail_key<T0: copy+ drop+ store, T1: store>(a0: &iterable_table::IterableTable<T0, T1>): option::Option<T0>;

}
