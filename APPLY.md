# How to apply this cleanup

Copy the files from this package into the root of your local YoutubePull
repository, replacing README.md and Resources/THIRD_PARTY_NOTICES.txt.

Then run:

```bash
git add LICENSE README.md THIRD_PARTY_SOURCES.md Resources/THIRD_PARTY_NOTICES.txt
git commit -m "Add licensing and third-party notices"
git push
```

After that, rebuild the standalone app with `./build.sh` before publishing a
Release so the third-party license files downloaded by the build script are
present inside the `.app`.

This is a best-effort licensing cleanup and not legal advice.
