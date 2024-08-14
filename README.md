# zig-tmpl

This was more of a learning exercise with the zig build system.

#### Objective

At build time:
- Search for a collection of files
- Parse the contents and return a compilable zig file
- Make that file available to the main program
- Lastly, only rebuild the file if there are changes

I have worked alot with the templates [Kendo UI for jQuery](https://docs.telerik.com/kendo-ui/framework/templates) so thought I chose to try implement a very simple version of how that works.

#### Findings

- This played out way easier than I expected after I found the [generating-zig-source-code](https://ziglang.org/learn/build-system/#generating-zig-source-code) under the zig build system of zig learn
- The build system is magical and figured out on its own to not rebuild the templates, nice!
- I think the above is only because I generated the templates through a run step, (as per the learn section). I'm not sure what the outcome would have been if I had to manage the file from within build.zig
