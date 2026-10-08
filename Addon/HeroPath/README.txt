Hero’sPath 1.0.0
Author: Darwyn

Install the HeroPath folder in Interface/AddOns/.

Diagnostics:
  /hp check
  /hp stats
  /hp pos
  /hp contract

Integration:
  Other addons should use the global HeroPathAPI table.
  Do not read or mutate HeroPathDB directly.

Safety:
  A SavedVariables schema newer than this build is opened in read-only archive mode.
  In that mode no sampling, mutation, repair, or compression is performed.
