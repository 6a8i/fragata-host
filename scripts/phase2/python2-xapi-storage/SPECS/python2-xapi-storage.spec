Summary: Xapi storage interface (Python 2)
Name: python2-xapi-storage
Version: 24.19.2
Release: 1.10.1%{?dist}
License: LGPL-2.1-only WITH OCaml-LGPL-linking-exception
URL: https://github.com/xapi-project/xen-api
# the sources of the xapi source package of XCP-ng 8.3 (xapi-24.19.2-1.10.xcpng8.3.src.rpm), the last one that
# ships this library: its xapi no longer builds with the current OCaml libraries of XCP-ng, the generator of this
# library (Python written by an OCaml program) does. build-python2-xapi-storage.sh takes it from the checked SRPM.
Source0: xen-api-%{version}.tar.gz
BuildArch: noarch
BuildRequires: xs-opam-repo
BuildRequires: python2-devel
BuildRequires: python2-setuptools
Requires: python2-future
Requires: python-six
Provides: xapi-storage = %{version}-%{release}
Obsoletes: xapi-storage < %{version}-%{release}

%description
Xapi storage interface libraries for python2, built from the sources of xapi %{version} for Fragata Host.

%prep
%autosetup -n xapi-%{version}

%build
export OCAMLPATH=%{_ocamlpath}
dune build @ocaml/xapi-storage/python/xapi/storage/api/v5/python
cd _build/default/ocaml/xapi-storage/python && %{py2_build}

%install
cd _build/default/ocaml/xapi-storage/python && %{py2_install}

%files
%license LICENSE
%{python2_sitelib}/xapi/__init__.py*
%{python2_sitelib}/xapi/storage/*
%exclude %{python2_sitelib}/*.egg-info

%changelog
* Sun Nov 08 2026 The Fragata project - 24.19.2-1.10.1
- Built from the sources of xapi 24.19.2 (XCP-ng 8.3), apart from xapi
