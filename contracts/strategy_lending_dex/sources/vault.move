module strategy_lending_dex::vault {
    public fun borrow_and_deposit() {
        moneyfi_lending::wrapper::borrow();

        moneyfi_dex::wrapper::deposit();
    }
}
