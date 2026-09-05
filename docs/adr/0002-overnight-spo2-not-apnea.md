# Overnight SpO2 is collected; apnea grades stay off-screen

F5/F7 dropped every SpO2 value. The sleep page now needs last night's oxygen as a measurement (mean, minimum, curve on the night's clock). The trade-off: reopen overnight automatic oxygen only, in its own SDK history table, and still refuse the vendor `osahsResult` mild/moderate/severe apnea labels — those read as diagnosis, which F5 §06 forbids.
