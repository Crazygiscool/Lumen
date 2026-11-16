Name: lumen
Version: %{_version}
Release: 1%{?dist}
Summary: Private, encrypted Markdown journal
License: Lumen Non-Commercial Software License v1.0
URL: https://github.com/Crazygiscool/Lumen
Source0: %{name}-%{version}.tar.gz
BuildArch: %{_arch}

%description
Lumen is an offline-first journal with AES-256-GCM encrypted notes,
Markdown editing, imports, plugins, and a terminal client.

%prep
%setup -q

%build
# No build step: the Flutter + Rust bundle is prebuilt by build_linux.sh.

%install
install -d %{buildroot}%{_datadir}/lumen
install -d %{buildroot}%{_bindir}
install -d %{buildroot}%{_datadir}/applications
install -d %{buildroot}%{_datadir}/icons/hicolor/1024x1024/apps
install -d %{buildroot}%{_docdir}/%{name}

cp -a bundle/* %{buildroot}%{_datadir}/lumen/

# Launch wrappers. The Flutter bundle stays together in %{_datadir}/lumen.
ln -sf %{_datadir}/lumen/lumen %{buildroot}%{_bindir}/lumen

install -Dm644 scripts/lumen.desktop \
    %{buildroot}%{_datadir}/applications/lumen.desktop
install -Dm644 ui/lib/assets/lumen_logo.png \
    %{buildroot}%{_datadir}/icons/hicolor/1024x1024/apps/lumen.png
install -Dm644 LICENSE %{buildroot}%{_docdir}/%{name}/copyright

%files
%{_bindir}/lumen
%{_datadir}/lumen/*
%{_datadir}/applications/lumen.desktop
%{_datadir}/icons/hicolor/1024x1024/apps/lumen.png
%{_docdir}/%{name}/copyright

%changelog
* Thu Nov 13 2026 Crazygiscool <crazygiscool@proton.me> - %{version}-1
- Initial RPM package
