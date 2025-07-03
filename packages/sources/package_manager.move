module moneyfi::package_manager {
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::resource_account;
    use aptos_framework::code;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::simple_map::{Self, SimpleMap};
    use std::string::String;
    use std::signer;

    friend moneyfi::fund_vault;

    //CONSTANT
    const ADMIN: u64 = 1;
    const DELEGATE: u64 = 2;
    const OPERATOR: u64 = 3;

    /// Stores permission config such as SignerCapability for controlling the resource account.
    struct PermissionConfig has key {
        /// Required to obtain the resource account signer.
        signer_cap: SignerCapability,
        /// Track the addresses created by the modules in this package.
        addresses: SmartTable<String, address>,
        /// Track the permissions of each address.
        roles: SmartTable<u64, SimpleMap<address, bool>>
    }

    /// Initialize PermissionConfig to establish control over the resource account.
    /// This function is invoked only when this package is deployed the first time.
    fun init_module(package_signer: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(package_signer, @deployer);
        
        let roles = smart_table::new<u64, SimpleMap<address, bool>>();
        smart_table::add(&mut roles, ADMIN, simple_map::new<address, bool>());
        smart_table::add(&mut roles, DELEGATE, simple_map::new<address, bool>());
        smart_table::add(&mut roles, OPERATOR, simple_map::new<address, bool>());
        move_to(
            package_signer,
            PermissionConfig {
                addresses: smart_table::new<String, address>(),
                signer_cap,
                roles,
            }
        );
    }

    public entry fun update_package(
        owner: &signer, metadata_serialized: vector<u8>, code: vector<vector<u8>>
    ) acquires PermissionConfig {
        let package_signer = &get_signer();
        assert!(signer::address_of(owner) == @deployer, 0x1);
        code::publish_package_txn(package_signer, metadata_serialized, code);
    }

    /// Can be called by friended modules to obtain the resource account signer.
    public(friend) fun get_signer(): signer acquires PermissionConfig {
        let signer_cap = &borrow_global<PermissionConfig>(@moneyfi).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    /// Can be called by friended modules to keep track of a system address.
    public(friend) fun add_address(name: String, object: address) acquires PermissionConfig {
        let addresses = &mut borrow_global_mut<PermissionConfig>(@moneyfi).addresses;
        smart_table::add(addresses, name, object);
    }

    public fun address_exists(name: String): bool acquires PermissionConfig {
        smart_table::contains(&safe_permission_config().addresses, name)
    }

    public fun get_address(name: String): address acquires PermissionConfig {
        let addresses = &borrow_global<PermissionConfig>(@moneyfi).addresses;
        *smart_table::borrow(addresses, name)
    }

    inline fun safe_permission_config(): &PermissionConfig acquires PermissionConfig {
        borrow_global<PermissionConfig>(@moneyfi)
    }
}
