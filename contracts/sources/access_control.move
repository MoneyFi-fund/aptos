module moneyfi::access_control {
	use std::signer;
	use aptos_std::table::{Self, Table};

	// -- Roles
	const ROLE_ADMIN: u8 = 1;
	const ROLE_OPERATOR: u8 = 2;

	// -- Error Codes
	const E_ALREADY_INITIALIZED: u64 = 1;
	const E_NOT_AUTHORIZED: u64 = 2;
	const E_INVALID_PARAM: u64 = 3;

	struct RoleRegistry has key {
		roles: Table<address, u8>
	}

	#[test_only]
	friend moneyfi::access_control_test;

	fun init_module(sender: &signer) {
		initialize(sender)
	}

	friend fun initialize(sender: &signer) {
		let addr = signer::address_of(sender);
		assert!(!exists<RoleRegistry>(addr), E_ALREADY_INITIALIZED);

		let roles = table::new<address, u8>();
		table::add(&mut roles, addr, ROLE_ADMIN);

		move_to(sender, RoleRegistry { roles });
	}

	public entry fun set_role(sender: &signer, addr: address, role: u8) acquires RoleRegistry {
		assert!(role == ROLE_ADMIN || role == ROLE_OPERATOR, E_INVALID_PARAM);
		assert!(is_admin(sender), E_NOT_AUTHORIZED);

		let registry = borrow_global_mut<RoleRegistry>(@moneyfi);
		table::upsert(&mut registry.roles, addr, role);

		// TODO: dispatch event
	}

	public entry fun revoke(sender: &signer, addr: address ) acquires RoleRegistry {
		assert!(is_admin(sender), E_NOT_AUTHORIZED);
		let registry = borrow_global_mut<RoleRegistry>(@moneyfi);
		if (table::contains(&registry.roles, addr)) {
			table::remove(&mut registry.roles, addr);

			// TODO: dispatch event
		}
	}


	fun has_role(addr: address, role: u8): bool acquires RoleRegistry {
		let registry = borrow_global<RoleRegistry>(@moneyfi);
		
		if (table::contains(&registry.roles, addr)) {
			table::borrow(&registry.roles, addr) == &role
		} else {
			false
		}
	}

	public fun is_admin(sender: &signer): bool acquires RoleRegistry {
		let addr = signer::address_of(sender);
		
		has_role(addr, ROLE_ADMIN)
	}

	public fun is_operator(sender: &signer): bool acquires RoleRegistry {
		let addr = signer::address_of(sender);
		
		has_role(addr, ROLE_OPERATOR)
	}
}